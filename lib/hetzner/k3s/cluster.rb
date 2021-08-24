require 'thread'
require 'net/ssh'
require "securerandom"
require "base64"
require "k8s-ruby"
require 'timeout'

require_relative "../infra/client"
require_relative "../infra/firewall"
require_relative "../infra/network"
require_relative "../infra/ssh_key"
require_relative "../infra/server"
require_relative "../infra/load_balancer"

require_relative "../k3s/client_patch"


class Cluster
  def initialize(hetzner_client:, hetzner_token:)
    @hetzner_client = hetzner_client
    @hetzner_token = hetzner_token
  end

  def create(configuration:)
    @cluster_name = configuration.dig("cluster_name")
    @kubeconfig_path = File.expand_path(configuration.dig("kubeconfig_path"))
    @ssh_key_path = File.expand_path(configuration.dig("ssh_key_path"))
    @k3s_version = configuration.dig("k3s_version")
    @masters_config = configuration.dig("masters")
    @worker_node_pools = configuration.dig("worker_node_pools")
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
    @ssh_key_path = File.expand_path(configuration.dig("ssh_key_path"))

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

    attr_accessor :servers

    attr_reader :hetzner_client, :cluster_name, :kubeconfig_path, :k3s_version,
                :masters_config, :worker_node_pools,
                :location, :ssh_key_path, :kubernetes_client,
                :hetzner_token, :tls_sans, :new_k3s_version, :configuration,
                :config_file, :verify_host_key, :networks


    def latest_k3s_version
      response = HTTP.get("https://api.github.com/repos/k3s-io/k3s/tags").body
      JSON.parse(response).first["name"]
    end

    def create_resources
      master_instance_type = masters_config["instance_type"]
      masters_count = masters_config["instance_count"]

      firewall_id = Hetzner::Firewall.new(
        hetzner_client: hetzner_client,
        cluster_name: cluster_name
      ).create(ha: (masters_count > 1), networks: networks)

      network_id = Hetzner::Network.new(
        hetzner_client: hetzner_client,
        cluster_name: cluster_name
      ).create

      ssh_key_id = Hetzner::SSHKey.new(
        hetzner_client: hetzner_client,
        cluster_name: cluster_name
      ).create(ssh_key_path: ssh_key_path)

      server_configs = []

      masters_count.times do |i|
        server_configs << {
          location: location,
          instance_type: master_instance_type,
          instance_id: "master#{i+1}",
          firewall_id: firewall_id,
          network_id: network_id,
          ssh_key_id: ssh_key_id
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
            ssh_key_id: ssh_key_id
          }
        end
      end

      threads = server_configs.map do |server_config|
        Thread.new do
          servers << Hetzner::Server.new(hetzner_client: hetzner_client, cluster_name: cluster_name).create(server_config)
        end
      end

      threads.each(&:join) unless threads.empty?

      puts
      threads = servers.map do |server|
        Thread.new { wait_for_ssh server }
      end

      threads.each(&:join) unless threads.empty?
    end

    def delete_resources
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
      ).delete(ssh_key_path: ssh_key_path)

      threads = all_servers.map do |server|
        Thread.new do
          Hetzner::Server.new(hetzner_client: hetzner_client, cluster_name: cluster_name).delete(server_name: server["name"])
        end
      end

      threads.each(&:join) unless threads.empty?
    end

    def upgrade_cluster
      resources = K8s::Resource.from_files(ugrade_plan_manifest_path)

      begin
        kubernetes_client.api("upgrade.cattle.io/v1").resource("plans").get("k3s-server", namespace: "system-upgrade")

        puts "Aborting - an upgrade is already in progress."

      rescue K8s::Error::NotFound
        resources.each do |resource|
          kubernetes_client.create_resource(resource)
        end

        puts "Upgrade will now start. Run `watch kubectl get nodes` to see the nodes being upgraded. This should take a few minutes for a small cluster."
        puts "The API server may be briefly unavailable during the upgrade of the controlplane."

        configuration["k3s_version"] = new_k3s_version

        File.write(config_file, configuration.to_yaml)
      end
    end


    def master_script(master)
      server = master == first_master ? " --cluster-init " : " --server https://#{first_master_private_ip}:6443 "
      flannel_interface = find_flannel_interface(master)

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
        --node-taint CriticalAddonsOnly=true:NoExecute \
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
      puts
      puts "Deploying Hetzner Cloud Controller Manager..."

      begin
        kubernetes_client.api("v1").resource("secrets").get("hcloud", namespace: "kube-system")

      rescue K8s::Error::NotFound
        secret = K8s::Resource.new(
          apiVersion: "v1",
          kind: "Secret",
          metadata: {
            namespace: 'kube-system',
            name: 'hcloud',
          },
          data: {
            network: Base64.encode64(cluster_name),
            token: Base64.encode64(hetzner_token)
          }
        )

        kubernetes_client.api('v1').resource('secrets').create_resource(secret)
      end


      manifest = HTTP.follow.get("https://github.com/hetznercloud/hcloud-cloud-controller-manager/releases/latest/download/ccm-networks.yaml").body

      File.write("/tmp/cloud-controller-manager.yaml", manifest)

      resources = K8s::Resource.from_files("/tmp/cloud-controller-manager.yaml")

      begin
        kubernetes_client.api("apps/v1").resource("deployments").get("hcloud-cloud-controller-manager", namespace: "kube-system")

        resources.each do |resource|
          kubernetes_client.update_resource(resource)
        end

      rescue K8s::Error::NotFound
        resources.each do |resource|
          kubernetes_client.create_resource(resource)
        end

      end

      puts "...Cloud Controller Manager deployed"
    rescue Excon::Error::Socket
      retry
    end

    def deploy_system_upgrade_controller
      puts
      puts "Deploying k3s System Upgrade Controller..."

      manifest = HTTP.follow.get("https://github.com/rancher/system-upgrade-controller/releases/download/v0.7.3/system-upgrade-controller.yaml").body

      File.write("/tmp/system-upgrade-controller.yaml", manifest)

      resources = K8s::Resource.from_files("/tmp/system-upgrade-controller.yaml")

      begin
        kubernetes_client.api("apps/v1").resource("deployments").get("system-upgrade-controller", namespace: "system-upgrade")

        resources.each do |resource|
          kubernetes_client.update_resource(resource)
        end

      rescue K8s::Error::NotFound
        resources.each do |resource|
          kubernetes_client.create_resource(resource)
        end

      end

      puts "...k3s System Upgrade Controller deployed"
    rescue Excon::Error::Socket
      retry
    end

    def deploy_csi_driver
      puts
      puts "Deploying Hetzner CSI Driver..."

      begin
        kubernetes_client.api("v1").resource("secrets").get("hcloud-csi", namespace: "kube-system")

      rescue K8s::Error::NotFound
        secret = K8s::Resource.new(
          apiVersion: "v1",
          kind: "Secret",
          metadata: {
            namespace: 'kube-system',
            name: 'hcloud-csi',
          },
          data: {
            token: Base64.encode64(hetzner_token)
          }
        )

        kubernetes_client.api('v1').resource('secrets').create_resource(secret)
      end


      manifest = HTTP.follow.get("https://raw.githubusercontent.com/hetznercloud/csi-driver/v1.5.3/deploy/kubernetes/hcloud-csi.yml").body

      File.write("/tmp/csi-driver.yaml", manifest)

      resources = K8s::Resource.from_files("/tmp/csi-driver.yaml")

      begin
        kubernetes_client.api("apps/v1").resource("daemonsets").get("hcloud-csi-node", namespace: "kube-system")


        resources.each do |resource|
          begin
            kubernetes_client.update_resource(resource)
          rescue K8s::Error::Invalid => e
            raise e unless e.message =~ /must be specified/i
          end
        end

      rescue K8s::Error::NotFound
        resources.each do |resource|
          kubernetes_client.create_resource(resource)
        end

      end

      puts "...CSI Driver deployed"
    rescue Excon::Error::Socket
      retry
    end

    def wait_for_ssh(server)
      Timeout::timeout(5) do
        server_name = server["name"]

        puts "Waiting for server #{server_name} to be up..."

        loop do
          result = ssh(server, "echo UP")
          break if result == "UP"
        end

        puts "...server #{server_name} is now up."
      end
    rescue Errno::ENETUNREACH, Errno::EHOSTUNREACH, Timeout::Error, IOError
      retry
    end

    def ssh(server, command, print_output: false)
      public_ip = server.dig("public_net", "ipv4", "ip")
      output = ""

      Net::SSH.start(public_ip, "root", verify_host_key: (verify_host_key ? :always : :never)) do |session|
        session.exec!(command) do |channel, stream, data|
          output << data
          puts data if print_output
        end
      end
      output.chop
    rescue Net::SSH::Disconnect => e
      retry unless e.message =~ /Too many authentication failures/
    rescue Net::SSH::ConnectionTimeout, Errno::ECONNREFUSED, Errno::ENETUNREACH, Errno::EHOSTUNREACH
      retry
    rescue Net::SSH::HostKeyMismatch
      puts
      puts "Cannot continue: Unable to SSH into server with IP #{public_ip} because the existing fingerprint in the known_hosts file does not match that of the actual host key."
      puts "This is due to a security check but can also happen when creating a new server that gets assigned the same IP address as another server you've owned in the past."
      puts "If are sure no security is being violated here and you're just creating new servers, you can eiher remove the relevant lines from your known_hosts (see IPs from the cloud console) or disable host key verification by setting the option 'verify_host_key' to false in the configuration file for the cluster."
      exit 1
    end

    def kubernetes_client
      return @kubernetes_client if @kubernetes_client

      config_hash = YAML.load_file(kubeconfig_path)
      config_hash['current-context'] = cluster_name
      @kubernetes_client = K8s::Client.config(K8s::Config.new(config_hash))
    end

    def find_flannel_interface(server)
      if ssh(server, "lscpu | grep Vendor") =~ /Intel/
        "ens10"
      else
        "enp7s0"
      end
    end

    def all_servers
      @all_servers ||= hetzner_client.get("/servers")["servers"].select{ |server| belongs_to_cluster?(server) == true }
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
    end

    def ugrade_plan_manifest_path
      worker_upgrade_concurrency = workers.size - 1
      worker_upgrade_concurrency = 1 if worker_upgrade_concurrency == 0

      manifest = <<~EOF
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
        ---
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

      temp_file_path = "/tmp/k3s-upgrade-plan.yaml"

      File.write(temp_file_path, manifest)

      temp_file_path
    end

    def belongs_to_cluster?(server)
      server.dig("labels", "cluster") == cluster_name
    end

end
