require 'thread'
require 'net/ssh'
require "securerandom"
require "base64"
require 'timeout'
require "subprocess"

require_relative "../infra/client"
require_relative "../infra/firewall"
require_relative "../infra/network"
require_relative "../infra/ssh_key"
require_relative "../infra/server"
require_relative "../infra/load_balancer"
require_relative "../infra/placement_group"

require_relative "../utils"


class Cluster
  include Utils

  def initialize(hetzner_client:, hetzner_token:)
    @hetzner_client = hetzner_client
    @hetzner_token = hetzner_token
  end

  def create(configuration:)
    @configuration = configuration
    @cluster_name = configuration.dig("cluster_name")
    @kubeconfig_path = File.expand_path(configuration.dig("kubeconfig_path"))
    @public_ssh_key_path = File.expand_path(configuration.dig("public_ssh_key_path"))
    private_ssh_key_path = configuration.dig("private_ssh_key_path")
    @private_ssh_key_path = File.expand_path(private_ssh_key_path) if private_ssh_key_path
    @k3s_version = configuration.dig("k3s_version")
    @masters_config = configuration.dig("masters")
    @worker_node_pools = find_worker_node_pools(configuration)
    @location = configuration.dig("location")
    @verify_host_key = configuration.fetch("verify_host_key", false)
    @servers = []
    @networks = configuration.dig("ssh_allowed_networks")

    create_resources

    deploy_kubernetes

    sleep 10

    deploy_cloud_controller_manager
    deploy_csi_driver
    deploy_system_upgrade_controller
  end

  def delete(configuration:)
    @cluster_name = configuration.dig("cluster_name")
    @kubeconfig_path = File.expand_path(configuration.dig("kubeconfig_path"))
    @public_ssh_key_path = File.expand_path(configuration.dig("public_ssh_key_path"))

    delete_resources
  end

  def upgrade(configuration:, new_k3s_version:, config_file:)
    @configuration = configuration
    @cluster_name = configuration.dig("cluster_name")
    @kubeconfig_path = File.expand_path(configuration.dig("kubeconfig_path"))
    @new_k3s_version = new_k3s_version
    @config_file = config_file

    upgrade_cluster
  end

  private

    def find_worker_node_pools(configuration)
      configuration.fetch("worker_node_pools", [])
    end

    attr_accessor :servers

    attr_reader :hetzner_client, :cluster_name, :kubeconfig_path, :k3s_version,
                :masters_config, :worker_node_pools,
                :location, :public_ssh_key_path,
                :hetzner_token, :tls_sans, :new_k3s_version, :configuration,
                :config_file, :verify_host_key, :networks, :private_ssh_key_path, :configuration


    def latest_k3s_version
      response = HTTP.get("https://api.github.com/repos/k3s-io/k3s/tags").body
      JSON.parse(response).first["name"]
    end

    def create_resources
      master_instance_type = masters_config["instance_type"]
      masters_count = masters_config["instance_count"]

      placement_group_id = Hetzner::PlacementGroup.new(
        hetzner_client: hetzner_client,
        cluster_name: cluster_name
      ).create

      firewall_id = Hetzner::Firewall.new(
        hetzner_client: hetzner_client,
        cluster_name: cluster_name
      ).create(ha: (masters_count > 1), networks: networks)

      network_id = Hetzner::Network.new(
        hetzner_client: hetzner_client,
        cluster_name: cluster_name
      ).create(location: location)

      ssh_key_id = Hetzner::SSHKey.new(
        hetzner_client: hetzner_client,
        cluster_name: cluster_name
      ).create(public_ssh_key_path: public_ssh_key_path)

      server_configs = []

      masters_count.times do |i|
        server_configs << {
          location: location,
          instance_type: master_instance_type,
          instance_id: "master#{i+1}",
          firewall_id: firewall_id,
          network_id: network_id,
          ssh_key_id: ssh_key_id,
          placement_group_id: placement_group_id,
          image: image,
          additional_packages: additional_packages,
        }
      end

      if masters_count > 1
        Hetzner::LoadBalancer.new(
          hetzner_client: hetzner_client,
          cluster_name: cluster_name
        ).create(location: location, network_id: network_id)
      end

      worker_node_pools.each do |worker_node_pool|
        worker_node_pool_name = worker_node_pool["name"]
        worker_instance_type = worker_node_pool["instance_type"]
        worker_count = worker_node_pool["instance_count"]

        worker_count.times do |i|
          server_configs << {
            location: location,
            instance_type: worker_instance_type,
            instance_id: "pool-#{worker_node_pool_name}-worker#{i+1}",
            firewall_id: firewall_id,
            network_id: network_id,
            ssh_key_id: ssh_key_id,
            placement_group_id: placement_group_id,
            image: image,
            additional_packages: additional_packages,
          }
        end
      end

      threads = server_configs.map do |server_config|
        Thread.new do
          servers << Hetzner::Server.new(hetzner_client: hetzner_client, cluster_name: cluster_name).create(**server_config)
        end
      end

      threads.each(&:join) unless threads.empty?

      while servers.size != server_configs.size
        sleep 1
      end

      puts
      threads = servers.map do |server|
        Thread.new { wait_for_ssh server }
      end

      threads.each(&:join) unless threads.empty?
    end

    def delete_resources
      Hetzner::PlacementGroup.new(
        hetzner_client: hetzner_client,
        cluster_name: cluster_name
      ).delete

      Hetzner::LoadBalancer.new(
        hetzner_client: hetzner_client,
        cluster_name: cluster_name
      ).delete(ha: (masters.size > 1))

      Hetzner::Firewall.new(
        hetzner_client: hetzner_client,
        cluster_name: cluster_name
      ).delete(all_servers)

      Hetzner::Network.new(
        hetzner_client: hetzner_client,
        cluster_name: cluster_name
      ).delete

      Hetzner::SSHKey.new(
        hetzner_client: hetzner_client,
        cluster_name: cluster_name
      ).delete(public_ssh_key_path: public_ssh_key_path)

      threads = all_servers.map do |server|
        Thread.new do
          Hetzner::Server.new(hetzner_client: hetzner_client, cluster_name: cluster_name).delete(server_name: server["name"])
        end
      end

      threads.each(&:join) unless threads.empty?
    end

    def upgrade_cluster
      worker_upgrade_concurrency = workers.size - 1
      worker_upgrade_concurrency = 1 if worker_upgrade_concurrency == 0

      cmd = <<~EOS
        kubectl apply -f - <<-EOF
          apiVersion: upgrade.cattle.io/v1
          kind: Plan
          metadata:
            name: k3s-server
            namespace: system-upgrade
            labels:
              k3s-upgrade: server
          spec:
            concurrency: 1
            version: #{new_k3s_version}
            nodeSelector:
              matchExpressions:
                - {key: node-role.kubernetes.io/master, operator: In, values: ["true"]}
            serviceAccountName: system-upgrade
            tolerations:
            - key: "CriticalAddonsOnly"
              operator: "Equal"
              value: "true"
              effect: "NoExecute"
            cordon: true
            upgrade:
              image: rancher/k3s-upgrade
        EOF
      EOS

      run cmd, kubeconfig_path: kubeconfig_path

      cmd = <<~EOS
        kubectl apply -f - <<-EOF
          apiVersion: upgrade.cattle.io/v1
          kind: Plan
          metadata:
            name: k3s-agent
            namespace: system-upgrade
            labels:
              k3s-upgrade: agent
          spec:
            concurrency: #{worker_upgrade_concurrency}
            version: #{new_k3s_version}
            nodeSelector:
              matchExpressions:
                - {key: node-role.kubernetes.io/master, operator: NotIn, values: ["true"]}
            serviceAccountName: system-upgrade
            prepare:
              image: rancher/k3s-upgrade
              args: ["prepare", "k3s-server"]
            cordon: true
            upgrade:
              image: rancher/k3s-upgrade
        EOF
      EOS

      run cmd, kubeconfig_path: kubeconfig_path

      puts "Upgrade will now start. Run `watch kubectl get nodes` to see the nodes being upgraded. This should take a few minutes for a small cluster."
      puts "The API server may be briefly unavailable during the upgrade of the controlplane."

      configuration["k3s_version"] = new_k3s_version

      File.write(config_file, configuration.to_yaml)
    end


    def master_script(master)
      server = master == first_master ? " --cluster-init " : " --server https://#{first_master_private_ip}:6443 "
      flannel_interface = find_flannel_interface(master)

      taint = schedule_workloads_on_masters? ? " " : " --node-taint CriticalAddonsOnly=true:NoExecute "

      <<~EOF
        curl -sfL https://get.k3s.io | INSTALL_K3S_VERSION="#{k3s_version}" K3S_TOKEN="#{k3s_token}" INSTALL_K3S_EXEC="server \
          --disable-cloud-controller \
          --disable servicelb \
          --disable traefik \
          --disable local-storage \
          --disable metrics-server \
          --write-kubeconfig-mode=644 \
          --node-name="$(hostname -f)" \
          --cluster-cidr=10.244.0.0/16 \
          --etcd-expose-metrics=true \
          --kube-controller-manager-arg="address=0.0.0.0" \
          --kube-controller-manager-arg="bind-address=0.0.0.0" \
          --kube-proxy-arg="metrics-bind-address=0.0.0.0" \
          --kube-scheduler-arg="address=0.0.0.0" \
          --kube-scheduler-arg="bind-address=0.0.0.0" \
          #{taint} \
          --kubelet-arg="cloud-provider=external" \
          --advertise-address=$(hostname -I | awk '{print $2}') \
          --node-ip=$(hostname -I | awk '{print $2}') \
          --node-external-ip=$(hostname -I | awk '{print $1}') \
          --flannel-iface=#{flannel_interface} \
          #{server} #{tls_sans}" sh -
      EOF
    end

    def worker_script(worker)
      flannel_interface = find_flannel_interface(worker)

      <<~EOF
        curl -sfL https://get.k3s.io | K3S_TOKEN="#{k3s_token}" INSTALL_K3S_VERSION="#{k3s_version}" K3S_URL=https://#{first_master_private_ip}:6443 INSTALL_K3S_EXEC="agent \
          --node-name="$(hostname -f)" \
          --kubelet-arg="cloud-provider=external" \
          --node-ip=$(hostname -I | awk '{print $2}') \
          --node-external-ip=$(hostname -I | awk '{print $1}') \
          --flannel-iface=#{flannel_interface}" sh -
      EOF
    end

    def deploy_kubernetes
      puts
      puts "Deploying k3s to first master (#{first_master["name"]})..."

      ssh first_master, master_script(first_master), print_output: true

      puts
      puts "...k3s has been deployed to first master."

      save_kubeconfig

      if masters.size > 1
        threads = masters[1..-1].map do |master|
          Thread.new do
            puts
            puts "Deploying k3s to master #{master["name"]}..."

            ssh master, master_script(master), print_output: true

            puts
            puts "...k3s has been deployed to master #{master["name"]}."
          end
        end

        threads.each(&:join) unless threads.empty?
      end

      threads = workers.map do |worker|
        Thread.new do
          puts
          puts "Deploying k3s to worker (#{worker["name"]})..."

          ssh worker, worker_script(worker), print_output: true

          puts
          puts "...k3s has been deployed to worker (#{worker["name"]})."
        end
      end

      threads.each(&:join) unless threads.empty?
    end

    def deploy_cloud_controller_manager
      check_kubectl

      puts
      puts "Deploying Hetzner Cloud Controller Manager..."

      cmd = <<~EOS
        kubectl apply -f - <<-EOF
          apiVersion: "v1"
          kind: "Secret"
          metadata:
            namespace: 'kube-system'
            name: 'hcloud'
          stringData:
            network: "#{cluster_name}"
            token: "#{hetzner_token}"
        EOF
      EOS

      run cmd, kubeconfig_path: kubeconfig_path

      cmd = "kubectl apply -f https://github.com/hetznercloud/hcloud-cloud-controller-manager/releases/latest/download/ccm-networks.yaml"

      run cmd, kubeconfig_path: kubeconfig_path

      puts "...Cloud Controller Manager deployed"
    end

    def deploy_system_upgrade_controller
      check_kubectl

      puts
      puts "Deploying k3s System Upgrade Controller..."

      cmd = "kubectl apply -f https://github.com/rancher/system-upgrade-controller/releases/download/v0.8.1/system-upgrade-controller.yaml"

      run cmd, kubeconfig_path: kubeconfig_path

      puts "...k3s System Upgrade Controller deployed"
    end

    def deploy_csi_driver
      check_kubectl

      puts
      puts "Deploying Hetzner CSI Driver..."

      cmd = <<~EOS
        kubectl apply -f - <<-EOF
          apiVersion: "v1"
          kind: "Secret"
          metadata:
            namespace: 'kube-system'
            name: 'hcloud-csi'
          stringData:
            token: "#{hetzner_token}"
        EOF
      EOS

      run cmd, kubeconfig_path: kubeconfig_path

      cmd = "kubectl apply -f https://raw.githubusercontent.com/hetznercloud/csi-driver/v1.6.0/deploy/kubernetes/hcloud-csi.yml"

      run cmd, kubeconfig_path: kubeconfig_path

      puts "...CSI Driver deployed"
    end

    def find_flannel_interface(server)
      if ssh(server, "lscpu | grep Vendor") =~ /Intel/
        "ens10"
      else
        "enp7s0"
      end
    end

    def all_servers
      @all_servers ||= hetzner_client.get("/servers?sort=created:desc")["servers"].select{ |server| belongs_to_cluster?(server) == true }
    end

    def masters
      @masters ||= all_servers.select{ |server| server["name"] =~ /master\d+\Z/ }.sort{ |a, b| a["name"] <=> b["name"] }
    end

    def workers
      @workers = all_servers.select{ |server| server["name"] =~ /worker\d+\Z/ }.sort{ |a, b| a["name"] <=> b["name"] }
    end

    def k3s_token
      @k3s_token ||= begin
        token = ssh(first_master, "{ TOKEN=$(< /var/lib/rancher/k3s/server/node-token); } 2> /dev/null; echo $TOKEN")

        if token.empty?
          SecureRandom.hex
        else
          token.split(":").last
        end
      end
    end

    def first_master_private_ip
      @first_master_private_ip ||= first_master["private_net"][0]["ip"]
    end

    def first_master
      masters.first
    end

    def api_server_ip
      return @api_server_ip if @api_server_ip

      @api_server_ip = if masters.size > 1
        load_balancer_name = "#{cluster_name}-api"
        load_balancer = hetzner_client.get("/load_balancers")["load_balancers"].detect{ |load_balancer| load_balancer["name"] == load_balancer_name }
        load_balancer["public_net"]["ipv4"]["ip"]
      else
        first_master_public_ip
      end
    end

    def tls_sans
      sans = " --tls-san=#{api_server_ip} "

      masters.each do |master|
        master_private_ip = master["private_net"][0]["ip"]
        sans << " --tls-san=#{master_private_ip} "
      end

      sans
    end

    def first_master_public_ip
      @first_master_public_ip ||= first_master.dig("public_net", "ipv4", "ip")
    end

    def save_kubeconfig
      kubeconfig = ssh(first_master, "cat /etc/rancher/k3s/k3s.yaml").
        gsub("127.0.0.1", api_server_ip).
        gsub("default", cluster_name)

      File.write(kubeconfig_path, kubeconfig)

      FileUtils.chmod "go-r", kubeconfig_path
    end

    def belongs_to_cluster?(server)
      server.dig("labels", "cluster") == cluster_name
    end

    def schedule_workloads_on_masters?
      schedule_workloads_on_masters = configuration.dig("schedule_workloads_on_masters")
      schedule_workloads_on_masters ? !!schedule_workloads_on_masters : false
    end

    def image
      configuration.dig("image") || "ubuntu-20.04"
    end

    def additional_packages
      configuration.dig("additional_packages") || []
    end

    def check_kubectl
      unless which("kubectl")
        puts "Please ensure kubectl is installed and in your PATH."
        exit 1
      end
    end

end
