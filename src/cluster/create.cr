require "../configuration/main"
require "../configuration/loader"
require "../hetzner/client"
require "../hetzner/placement_group/create"
require "../hetzner/ssh_key/create"
require "../hetzner/firewall/create"
require "../hetzner/network/create"
require "../hetzner/instance/create"
require "../hetzner/load_balancer/create"
require "../util/ssh"
require "../kubernetes/installer"
require "../util/ssh"

class Cluster::Create
  MAX_INSTANCES_PER_PLACEMENT_GROUP = 7

  private getter configuration : Configuration::Loader
  private getter hetzner_client : Hetzner::Client do
    configuration.hetzner_client
  end
  private getter settings : Configuration::Main do
    configuration.settings
  end
  private getter public_ssh_key_path : String do
    configuration.public_ssh_key_path
  end
  private getter private_ssh_key_path : String do
    configuration.private_ssh_key_path
  end
  private getter masters : Array(Hetzner::Instance) do
    instances.select { |instance| instance.master? }.sort_by(&.name)
  end
  private getter workers : Array(Hetzner::Instance) do
    instances.select { |instance| instance.master? }.sort_by(&.name)
  end
  private getter autoscaling_worker_node_pools : Array(Configuration::NodePool) do
    settings.worker_node_pools.select(&.autoscaling_enabled)
  end
  private getter kubernetes_installer : Kubernetes::Installer do
    Kubernetes::Installer.new(configuration, load_balancer, ssh, autoscaling_worker_node_pools)
  end
  private getter ssh : Util::SSH do
    Util::SSH.new(private_ssh_key_path, public_ssh_key_path)
  end

  private getter network : Hetzner::Network
  private getter firewall : Hetzner::Firewall
  private getter ssh_key : Hetzner::SSHKey
  private getter load_balancer : Hetzner::LoadBalancer?
  private getter placement_groups : Hash(String, Hetzner::PlacementGroup?) = Hash(String, Hetzner::PlacementGroup?).new
  private property instances : Array(Hetzner::Instance) = [] of Hetzner::Instance
  private property master_instance_creators : Array(Hetzner::Instance::Create) do
    initialize_masters
  end
  private property worker_instance_creators : Array(Hetzner::Instance::Create) do
    initialize_worker_nodes
  end

  private property kubernetes_masters_installation_queue_channel do
    Channel(Hetzner::Instance).new
  end
  private property kubernetes_workers_installation_queue_channel do
    Channel(Hetzner::Instance).new
  end

  private property mutex : Mutex = Mutex.new

  def initialize(@configuration)
    @network = find_or_create_network.not_nil!
    @firewall = create_firewall
    @ssh_key = create_ssh_key
  end

  def run
    create_instances
  end

  private def initialize_masters
    creators = Array(Hetzner::Instance::Create).new

    masters_pool = settings.masters_pool
    placement_group = create_placement_group

    masters_pool.instance_count.times do |i|
      creators << create_master_instance(i, placement_group)
    end

    creators
  end

  private def create_placement_group
    Hetzner::PlacementGroup::Create.new(
      hetzner_client: hetzner_client,
      placement_group_name: "#{settings.cluster_name}-masters"
    ).run
  end

  private def create_master_instance(index : Int32, placement_group)
    instance_type = settings.masters_pool.instance_type
    master_name = "#{settings.cluster_name}-#{instance_type}-master#{index + 1}"
    image = settings.masters_pool.image || settings.image
    additional_packages = settings.masters_pool.additional_packages || settings.additional_packages
    additional_post_create_commands = settings.masters_pool.post_create_commands || settings.post_create_commands

    Hetzner::Instance::Create.new(
      mutex: mutex,
      settings: settings,
      hetzner_client: hetzner_client,
      cluster_name: settings.cluster_name,
      instance_name: master_name,
      instance_type: instance_type,
      image: image,
      snapshot_os: settings.snapshot_os,
      location: settings.masters_pool.location,
      placement_group: placement_group,
      ssh_key: ssh_key,
      firewall: firewall,
      network: network,
      ssh_port: settings.ssh_port,
      enable_public_net_ipv4: settings.enable_public_net_ipv4,
      enable_public_net_ipv6: settings.enable_public_net_ipv6,
      private_ssh_key_path: private_ssh_key_path,
      public_ssh_key_path: public_ssh_key_path,
      additional_packages: additional_packages,
      additional_post_create_commands: additional_post_create_commands
    )
  end

  private def initialize_worker_nodes
    creators = Array(Hetzner::Instance::Create).new
    no_autoscaling_worker_node_pools = settings.worker_node_pools.reject(&.autoscaling_enabled)

    no_autoscaling_worker_node_pools.each do |node_pool|
      placement_groups = create_placement_groups_for_node_pool(node_pool)

      node_pool.instance_count.times do |i|
        placement_group = placement_groups[i % placement_groups.size]
        creators << create_worker_instance(i, node_pool, placement_group)
      end
    end

    creators
  end

  private def create_placement_groups_for_node_pool(node_pool)
    placement_groups_count = (node_pool.instance_count / MAX_INSTANCES_PER_PLACEMENT_GROUP).ceil

    (1..placement_groups_count).map do |index|
      placement_group_name = "#{settings.cluster_name}-#{node_pool.name}-#{index}"

      Hetzner::PlacementGroup::Create.new(
        hetzner_client: hetzner_client,
        placement_group_name: placement_group_name
      ).run
    end
  end

  private def create_worker_instance(index : Int32, node_pool, placement_group)
    instance_type = node_pool.instance_type
    node_name = "#{settings.cluster_name}-#{instance_type}-pool-#{node_pool.name}-worker#{index + 1}"
    image = node_pool.image || settings.image
    additional_packages = node_pool.additional_packages || settings.additional_packages
    additional_post_create_commands = node_pool.post_create_commands || settings.post_create_commands

    Hetzner::Instance::Create.new(
      mutex: mutex,
      settings: settings,
      hetzner_client: hetzner_client,
      cluster_name: settings.cluster_name,
      instance_name: node_name,
      instance_type: instance_type,
      image: image,
      snapshot_os: settings.snapshot_os,
      location: node_pool.location,
      placement_group: placement_group,
      ssh_key: ssh_key,
      firewall: firewall,
      network: network,
      ssh_port: settings.ssh_port,
      enable_public_net_ipv4: settings.enable_public_net_ipv4,
      enable_public_net_ipv6: settings.enable_public_net_ipv6,
      private_ssh_key_path: private_ssh_key_path,
      public_ssh_key_path: public_ssh_key_path,
      additional_packages: additional_packages,
      additional_post_create_commands: additional_post_create_commands
    )
  end

  private def create_load_balancer
    @load_balancer = Hetzner::LoadBalancer::Create.new(
      hetzner_client: hetzner_client,
      cluster_name: settings.cluster_name,
      location: configuration.masters_location,
      network_id: network.id
    ).run
  end

  private def create_instances_concurrently(instance_creators, kubernetes_installation_queue_channel)
    instance_creators.each do |instance_creator|
      spawn do
        instance = instance_creator.run
        kubernetes_installation_queue_channel.send(instance)
      end
    end
  end

  private def create_instances
    create_instances_concurrently(master_instance_creators, kubernetes_masters_installation_queue_channel)
    create_instances_concurrently(worker_instance_creators, kubernetes_workers_installation_queue_channel)

    create_load_balancer if settings.masters_pool.instance_count > 1

    kubernetes_installer.run(
      masters_installation_queue_channel: kubernetes_masters_installation_queue_channel,
      workers_installation_queue_channel: kubernetes_workers_installation_queue_channel,
      master_count: master_instance_creators.size,
      worker_count: worker_instance_creators.size
    )
  end

  private def find_network
    existing_network_name = settings.existing_network

    return find_existing_network(existing_network_name) if existing_network_name
    create_new_network
  end

  private def find_existing_network(existing_network_name)
    Hetzner::Network::Find.new(hetzner_client, existing_network_name).run
  end

  private def create_new_network
    Hetzner::Network::Create.new(
      hetzner_client: hetzner_client,
      network_name: settings.cluster_name,
      location: settings.masters_pool.location,
      locations: configuration.locations,
      private_network: settings.private_network
    ).run
  end

  private def find_or_create_network
    find_network || create_new_network
  end

  private def create_firewall
    Hetzner::Firewall::Create.new(
      hetzner_client: hetzner_client,
      firewall_name: settings.cluster_name,
      ssh_allowed_networks: settings.ssh_allowed_networks,
      api_allowed_networks: settings.api_allowed_networks,
      high_availability: settings.masters_pool.instance_count > 1,
      private_network: settings.private_network,
      ssh_port: settings.ssh_port
    ).run
  end

  private def create_ssh_key
    Hetzner::SSHKey::Create.new(
      hetzner_client: hetzner_client,
      ssh_key_name: settings.cluster_name,
      public_ssh_key_path: public_ssh_key_path
    ).run
  end

  private def default_log_prefix
    "Cluster create"
  end
end
