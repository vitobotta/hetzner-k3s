# frozen_string_literal: true

require 'net/ssh'
require 'securerandom'
require 'base64'
require 'timeout'
require 'subprocess'

require_relative '../infra/client'
require_relative '../infra/firewall'
require_relative '../infra/network'
require_relative '../infra/ssh_key'
require_relative '../infra/server'
require_relative '../infra/load_balancer'
require_relative '../infra/placement_group'

require_relative '../utils'

class Cluster
  include Utils

  def initialize(configuration:)
    @configuration = configuration
  end

  def create
    @cluster_name = configuration['cluster_name']
    @kubeconfig_path = File.expand_path(configuration['kubeconfig_path'])
    @public_ssh_key_path = File.expand_path(configuration['public_ssh_key_path'])
    private_ssh_key_path = configuration['private_ssh_key_path']
    @private_ssh_key_path = private_ssh_key_path && File.expand_path(private_ssh_key_path)
    @k3s_version = configuration['k3s_version']
    @masters_config = configuration['masters']
    @worker_node_pools = find_worker_node_pools(configuration)
    @masters_location = configuration['location']
    @verify_host_key = configuration.fetch('verify_host_key', false)
    @servers = []
    @ssh_networks = configuration['ssh_allowed_networks']
    @api_networks = configuration['api_allowed_networks']
    @enable_encryption = configuration.fetch('enable_encryption', false)
    @kube_api_server_args = configuration.fetch('kube_api_server_args', [])
    @kube_scheduler_args = configuration.fetch('kube_scheduler_args', [])
    @kube_controller_manager_args = configuration.fetch('kube_controller_manager_args', [])
    @kube_cloud_controller_manager_args = configuration.fetch('kube_cloud_controller_manager_args', [])
    @kubelet_args = configuration.fetch('kubelet_args', [])
    @kube_proxy_args = configuration.fetch('kube_proxy_args', [])

    create_resources

    deploy_kubernetes

    sleep 10

    deploy_cloud_controller_manager
    deploy_csi_driver
    deploy_system_upgrade_controller
  end

  def delete
    @cluster_name = configuration['cluster_name']
    @kubeconfig_path = File.expand_path(configuration['kubeconfig_path'])
    @public_ssh_key_path = File.expand_path(configuration['public_ssh_key_path'])
    @masters_config = configuration['masters']
    @worker_node_pools = find_worker_node_pools(configuration)

    delete_resources
  end

  def upgrade(new_k3s_version:, config_file:)
    @cluster_name = configuration['cluster_name']
    @kubeconfig_path = File.expand_path(configuration['kubeconfig_path'])
    @new_k3s_version = new_k3s_version
    @config_file = config_file

    upgrade_cluster
  end

  private

  attr_accessor :servers

  attr_reader :configuration, :cluster_name, :kubeconfig_path, :k3s_version,
              :masters_config, :worker_node_pools,
              :masters_location, :public_ssh_key_path,
              :hetzner_token, :new_k3s_version,
              :config_file, :verify_host_key, :ssh_networks, :private_ssh_key_path,
              :enable_encryption, :kube_api_server_args, :kube_scheduler_args,
              :kube_controller_manager_args, :kube_cloud_controller_manager_args,
              :kubelet_args, :kube_proxy_args, :api_networks

  def find_worker_node_pools(configuration)
    configuration.fetch('worker_node_pools', [])
  end

  def latest_k3s_version
    response = HTTP.get('https://api.github.com/repos/k3s-io/k3s/tags').body
    JSON.parse(response).first['name']
  end

  def create_resources
    create_servers
    create_load_balancer if masters.size > 1
  end

  def delete_placement_groups
    Hetzner::PlacementGroup.new(hetzner_client:, cluster_name:).delete

    worker_node_pools.each do |pool|
      pool_name = pool['name']
      Hetzner::PlacementGroup.new(hetzner_client:, cluster_name:, pool_name:).delete
    end
  end

  def delete_resources
    Hetzner::LoadBalancer.new(hetzner_client:, cluster_name:).delete(high_availability: (masters.size > 1))

    Hetzner::Firewall.new(hetzner_client:, cluster_name:).delete(all_servers)

    Hetzner::Network.new(hetzner_client:, cluster_name:, existing_network:).delete

    Hetzner::SSHKey.new(hetzner_client:, cluster_name:).delete(public_ssh_key_path:)

    delete_placement_groups
    delete_servers
  end

  def upgrade_cluster
    worker_upgrade_concurrency = workers.size - 1
    worker_upgrade_concurrency = 1 if worker_upgrade_concurrency.zero?

    cmd = <<~BASH
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
    BASH

    run cmd, kubeconfig_path: kubeconfig_path

    cmd = <<~BASH
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
    BASH

    run cmd, kubeconfig_path: kubeconfig_path

    puts 'Upgrade will now start. Run `watch kubectl get nodes` to see the nodes being upgraded. This should take a few minutes for a small cluster.'
    puts 'The API server may be briefly unavailable during the upgrade of the controlplane.'

    updated_configuration = configuration.raw
    updated_configuration['k3s_version'] = new_k3s_version

    File.write(config_file, updated_configuration.to_yaml)
  end

  def master_script(master)
    server = master == first_master ? ' --cluster-init ' : " --server https://#{api_server_ip}:6443 "
    flannel_interface = find_flannel_interface(master)

    available_k3s_releases = Hetzner::Configuration.available_releases
    wireguard_native_min_version_index = available_k3s_releases.find_index('v1.23.6+k3s1')
    selected_version_index = available_k3s_releases.find_index(k3s_version)

    flannel_wireguard = if enable_encryption
      if selected_version_index >= wireguard_native_min_version_index
        ' --flannel-backend=wireguard-native '
      else
        ' --flannel-backend=wireguard '
      end
    else
      ' '
    end

    extra_args = "#{kube_api_server_args_list} #{kube_scheduler_args_list} #{kube_controller_manager_args_list} #{kube_cloud_controller_manager_args_list} #{kubelet_args_list} #{kube_proxy_args_list}"
    taint = schedule_workloads_on_masters? ? ' ' : ' --node-taint CriticalAddonsOnly=true:NoExecute '

    <<~SCRIPT
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
        #{flannel_wireguard} \
        --kube-controller-manager-arg="bind-address=0.0.0.0" \
        --kube-proxy-arg="metrics-bind-address=0.0.0.0" \
        --kube-scheduler-arg="bind-address=0.0.0.0" \
        #{taint} #{extra_args} \
        --kubelet-arg="cloud-provider=external" \
        --advertise-address=$(hostname -I | awk '{print $2}') \
        --node-ip=$(hostname -I | awk '{print $2}') \
        --node-external-ip=$(hostname -I | awk '{print $1}') \
        --flannel-iface=#{flannel_interface} \
        #{server} #{tls_sans}" sh -
    SCRIPT
  end

  def worker_script(worker)
    flannel_interface = find_flannel_interface(worker)

    <<~BASH
      curl -sfL https://get.k3s.io | K3S_TOKEN="#{k3s_token}" INSTALL_K3S_VERSION="#{k3s_version}" K3S_URL=https://#{first_master_private_ip}:6443 INSTALL_K3S_EXEC="agent \
        --node-name="$(hostname -f)" \
        --kubelet-arg="cloud-provider=external" \
        --node-ip=$(hostname -I | awk '{print $2}') \
        --node-external-ip=$(hostname -I | awk '{print $1}') \
        --flannel-iface=#{flannel_interface}" sh -
    BASH
  end

  def deploy_kubernetes
    puts
    puts "Deploying k3s to first master (#{first_master['name']})..."

    ssh first_master, master_script(first_master), print_output: true

    puts
    puts '...k3s has been deployed to first master.'

    save_kubeconfig

    if masters.size > 1
      threads = masters[1..].map do |master|
        Thread.new do
          puts
          puts "Deploying k3s to master #{master['name']}..."

          ssh master, master_script(master), print_output: true

          puts
          puts "...k3s has been deployed to master #{master['name']}."
        end
      end

      threads.each(&:join) unless threads.empty?
    end

    threads = workers.map do |worker|
      Thread.new do
        puts
        puts "Deploying k3s to worker (#{worker['name']})..."

        ssh worker, worker_script(worker), print_output: true

        puts
        puts "...k3s has been deployed to worker (#{worker['name']})."
      end
    end

    threads.each(&:join) unless threads.empty?
  end

  def deploy_cloud_controller_manager
    check_kubectl

    puts
    puts 'Deploying Hetzner Cloud Controller Manager...'

    cmd = <<~BASH
      kubectl apply -f - <<-EOF
        apiVersion: "v1"
        kind: "Secret"
        metadata:
          namespace: 'kube-system'
          name: 'hcloud'
        stringData:
          network: "#{existing_network || cluster_name}"
          token: "#{configuration.hetzner_token}"
      EOF
    BASH

    run cmd, kubeconfig_path: kubeconfig_path

    cmd = 'kubectl apply -f https://github.com/hetznercloud/hcloud-cloud-controller-manager/releases/latest/download/ccm-networks.yaml'

    run cmd, kubeconfig_path: kubeconfig_path

    puts '...Cloud Controller Manager deployed'
  end

  def deploy_system_upgrade_controller
    check_kubectl

    puts
    puts 'Deploying k3s System Upgrade Controller...'

    cmd = 'kubectl apply -f https://github.com/rancher/system-upgrade-controller/releases/download/v0.9.1/system-upgrade-controller.yaml'

    run cmd, kubeconfig_path: kubeconfig_path

    puts '...k3s System Upgrade Controller deployed'
  end

  def deploy_csi_driver
    check_kubectl

    puts
    puts 'Deploying Hetzner CSI Driver...'

    cmd = <<~BASH
      kubectl apply -f - <<-EOF
        apiVersion: "v1"
        kind: "Secret"
        metadata:
          namespace: 'kube-system'
          name: 'hcloud-csi'
        stringData:
          token: "#{configuration.hetzner_token}"
      EOF
    BASH

    run cmd, kubeconfig_path: kubeconfig_path

    cmd = 'kubectl apply -f https://raw.githubusercontent.com/hetznercloud/csi-driver/master/deploy/kubernetes/hcloud-csi.yml'

    run cmd, kubeconfig_path: kubeconfig_path

    puts '...CSI Driver deployed'
  end

  def find_flannel_interface(server)
    if ssh(server, 'lscpu | grep Vendor') =~ /Intel/
      'ens10'
    else
      'enp7s0'
    end
  end

  def all_servers
    @all_servers ||= hetzner_client.get('/servers?sort=created:desc')['servers'].select do |server|
      belongs_to_cluster?(server) == true
    end
  end

  def masters
    @masters ||= all_servers.select { |server| server['name'] =~ /master\d+\Z/ }.sort { |a, b| a['name'] <=> b['name'] }
  end

  def workers
    @workers = all_servers.select { |server| server['name'] =~ /worker\d+\Z/ }.sort { |a, b| a['name'] <=> b['name'] }
  end

  def k3s_token
    @k3s_token ||= begin
      token = ssh(first_master, '{ TOKEN=$(< /var/lib/rancher/k3s/server/node-token); } 2> /dev/null; echo $TOKEN')

      if token.empty?
        SecureRandom.hex
      else
        token.split(':').last
      end
    end
  end

  def first_master_private_ip
    @first_master_private_ip ||= first_master['private_net'][0]['ip']
  end

  def first_master
    masters.first
  end

  def api_server_ip
    return @api_server_ip if @api_server_ip

    @api_server_ip = if masters.size > 1
                       load_balancer_name = "#{cluster_name}-api"
                       load_balancer = hetzner_client.get('/load_balancers')['load_balancers'].detect do |lb|
                         lb['name'] == load_balancer_name
                       end
                       load_balancer['public_net']['ipv4']['ip']
                     else
                       first_master_public_ip
                     end
  end

  def tls_sans
    sans = " --tls-san=#{api_server_ip} "

    masters.each do |master|
      master_private_ip = master['private_net'][0]['ip']
      sans << " --tls-san=#{master_private_ip} "
    end

    sans
  end

  def first_master_public_ip
    @first_master_public_ip ||= first_master.dig('public_net', 'ipv4', 'ip')
  end

  def save_kubeconfig
    kubeconfig = ssh(first_master, 'cat /etc/rancher/k3s/k3s.yaml')
                 .gsub('127.0.0.1', api_server_ip)
                 .gsub('default', cluster_name)

    File.write(kubeconfig_path, kubeconfig)

    FileUtils.chmod 'go-r', kubeconfig_path
  end

  def belongs_to_cluster?(server)
    server.dig('labels', 'cluster') == cluster_name
  end

  def schedule_workloads_on_masters?
    schedule_workloads_on_masters = configuration['schedule_workloads_on_masters']
    schedule_workloads_on_masters ? !!schedule_workloads_on_masters : false
  end

  def image
    configuration['image'] || 'ubuntu-20.04'
  end

  def additional_packages
    configuration['additional_packages'] || []
  end

  def additional_post_create_commands
    configuration['post_create_commands'] || []
  end

  def check_kubectl
    return if which('kubectl')

    puts 'Please ensure kubectl is installed and in your PATH.'
    exit 1
  end

  def placement_group_id(pool_name = nil)
    @placement_groups ||= {}
    @placement_groups[pool_name || '__masters__'] ||= Hetzner::PlacementGroup.new(hetzner_client:, cluster_name:, pool_name:).create
  end

  def master_instance_type
    @master_instance_type ||= masters_config['instance_type']
  end

  def masters_count
    @masters_count ||= masters_config['instance_count']
  end

  def firewall_id
    @firewall_id ||= Hetzner::Firewall.new(hetzner_client:, cluster_name:).create(high_availability: (masters_count > 1), ssh_networks:, api_networks:)
  end

  def network_id
    @network_id ||= Hetzner::Network.new(hetzner_client:, cluster_name:, existing_network:).create(location: masters_location)
  end

  def ssh_key_id
    @ssh_key_id ||= Hetzner::SSHKey.new(hetzner_client:, cluster_name:).create(public_ssh_key_path:)
  end

  def master_definitions_for_create
    definitions = []

    masters_count.times do |i|
      definitions << {
        instance_type: master_instance_type,
        instance_id: "master#{i + 1}",
        location: masters_location,
        placement_group_id:,
        firewall_id:,
        network_id:,
        ssh_key_id:,
        image:,
        additional_packages:,
        additional_post_create_commands:
      }
    end

    definitions
  end

  def master_definitions_for_delete
    definitions = []

    masters_count.times do |i|
      definitions << {
        instance_type: master_instance_type,
        instance_id: "master#{i + 1}"
      }
    end

    definitions
  end

  def worker_node_pool_definitions(worker_node_pool)
    worker_node_pool_name = worker_node_pool['name']
    worker_instance_type = worker_node_pool['instance_type']
    worker_count = worker_node_pool['instance_count']
    worker_location = worker_node_pool['location'] || masters_location

    definitions = []

    worker_count.times do |i|
      definitions << {
        instance_type: worker_instance_type,
        instance_id: "pool-#{worker_node_pool_name}-worker#{i + 1}",
        placement_group_id: placement_group_id(worker_node_pool_name),
        location: worker_location,
        firewall_id:,
        network_id:,
        ssh_key_id:,
        image:,
        additional_packages:,
        additional_post_create_commands:
      }
    end

    definitions
  end

  def create_load_balancer
    Hetzner::LoadBalancer.new(hetzner_client:, cluster_name:).create(location: masters_location, network_id:)
  end

  def server_configs
    return @server_configs if @server_configs

    @server_configs = master_definitions_for_create

    worker_node_pools.each do |worker_node_pool|
      @server_configs += worker_node_pool_definitions(worker_node_pool)
    end

    @server_configs
  end

  def create_servers
    servers = []

    threads = server_configs.map do |server_config|
      Thread.new do
        servers << Hetzner::Server.new(hetzner_client:, cluster_name:).create(**server_config)
      end
    end

    threads.each(&:join) unless threads.empty?

    sleep 1 while servers.size != server_configs.size

    wait_for_servers(servers)
  end

  def wait_for_servers(servers)
    threads = servers.map do |server|
      Thread.new { wait_for_ssh server }
    end

    threads.each(&:join) unless threads.empty?
  end

  def delete_servers
    threads = all_servers.map do |server|
      Thread.new do
        Hetzner::Server.new(hetzner_client:, cluster_name:).delete(server_name: server['name'])
      end
    end

    threads.each(&:join) unless threads.empty?
  end

  def kube_api_server_args_list
    return '' if kube_api_server_args.empty?

    kube_api_server_args.map do |arg|
      " --kube-apiserver-arg=\"#{arg}\" "
    end.join
  end

  def kube_scheduler_args_list
    return '' if kube_scheduler_args.empty?

    kube_scheduler_args.map do |arg|
      " --kube-scheduler-arg=\"#{arg}\" "
    end.join
  end

  def kube_controller_manager_args_list
    return '' if kube_controller_manager_args.empty?

    kube_controller_manager_args.map do |arg|
      " --kube-controller-manager-arg=\"#{arg}\" "
    end.join
  end

  def kube_cloud_controller_manager_args_list
    return '' if kube_cloud_controller_manager_args.empty?

    kube_cloud_controller_manager_args.map do |arg|
      " --kube-cloud-controller-manager-arg=\"#{arg}\" "
    end.join
  end

  def kubelet_args_list
    return '' if kubelet_args.empty?

    kubelet_args.map do |arg|
      " --kubelet-arg=\"#{arg}\" "
    end.join
  end

  def kube_proxy_args_list
    return '' if kube_proxy_args.empty?

    kube_api_server_args.map do |arg|
      " --kube-proxy-arg=\"#{arg}\" "
    end.join
  end

  def hetzner_client
    configuration.hetzner_client
  end

  def existing_network
    configuration["existing_network"]
  end
end
