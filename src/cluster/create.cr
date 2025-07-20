require "../configuration/main"
require "../configuration/loader"
require "../hetzner/client"
require "../hetzner/placement_group/create"
require "../hetzner/placement_group/all"
require "../hetzner/ssh_key/create"
require "../hetzner/firewall/create"
require "../hetzner/network/create"
require "../hetzner/instance/create"
require "../hetzner/load_balancer/create"
require "../util/ssh"
require "../kubernetes/installer"

class Cluster::Create
  MAX_PLACEMENT_GROUPS = 50
  MAX_INSTANCES_PER_PLACEMENT_GROUP = 10 # Assuming this is the maximum number of instances per placement group

  private getter configuration : Configuration::Loader
  private getter hetzner_client : Hetzner::Client { configuration.hetzner_client }
  private getter settings : Configuration::Main { configuration.settings }
  private getter autoscaling_worker_node_pools : Array(Configuration::WorkerNodePool) { settings.worker_node_pools.select(&.autoscaling_enabled) }
  private getter ssh_client : Util::SSH { Util::SSH.new(settings.networking.ssh.private_key_path, settings.networking.ssh.public_key_path) }
  private getter network : Hetzner::Network?
  private getter ssh_key : Hetzner::SSHKey
  private getter load_balancer : Hetzner::LoadBalancer?
  private getter placement_groups : Hash(String, Hetzner::PlacementGroup?) = Hash(String, Hetzner::PlacementGroup?).new
  private getter master_instances : Array(Hetzner::Instance::Create)
  private getter worker_instances : Array(Hetzner::Instance::Create)
  private getter instances : Array(Hetzner::Instance) = [] of Hetzner::Instance

  private property kubernetes_masters_installation_queue_channel do
    Channel(Hetzner::Instance).new(5)
  end
  private property kubernetes_workers_installation_queue_channel do
    Channel(Hetzner::Instance).new(10)
  end
  private property completed_channel : Channel(Nil) = Channel(Nil).new
  private property mutex : Mutex = Mutex.new
  private property all_placement_groups : Array(Hetzner::PlacementGroup) = Array(Hetzner::PlacementGroup).new

  def initialize(@configuration)
    @network = find_or_create_network if settings.networking.private_network.enabled
    @ssh_key = create_ssh_key
    @all_placement_groups = Hetzner::PlacementGroup::All.new(settings, hetzner_client).delete_unused
    @master_instances = initialize_master_instances
    @worker_instances = initialize_worker_instances
  end

  def run
    create_instances_concurrently(master_instances, kubernetes_masters_installation_queue_channel, wait: true)

    configure_firewall if settings.networking.private_network.enabled || !settings.networking.public_network.use_local_firewall

    handle_load_balancer

    initiate_k3s_setup

    create_instances_concurrently(worker_instances, kubernetes_workers_installation_queue_channel)

    completed_channel.receive

    delete_unused_placement_groups

    warn_if_not_protected
  end

  private def handle_load_balancer
    if settings.create_load_balancer_for_the_kubernetes_api && master_instances.size > 1
      create_load_balancer
    else
      delete_load_balancer
    end
  end

  private def warn_if_not_protected
    unless settings.protect_against_deletion
      puts
      puts "WARNING!!! The cluster is not protected against deletion. If you want to protect the cluster against deletion, set `protect_against_deletion: true` in the configuration file.".colorize(:yellow)
      puts
    end
  end

  private def initiate_k3s_setup
    kubernetes_installer = Kubernetes::Installer.new(
      configuration,
      load_balancer,
      ssh_client,
      autoscaling_worker_node_pools
    )

    spawn do
      kubernetes_installer.run(
        masters_installation_queue_channel: kubernetes_masters_installation_queue_channel,
        workers_installation_queue_channel: kubernetes_workers_installation_queue_channel,
        completed_channel: completed_channel,
        master_count: master_instances.size,
        worker_count: worker_instances.size
      )
    end
  end

  private def default_log_prefix
    "Cluster create"
  end

  ### Instances

  def build_instance_name(instance_type, index, include_instance_type, prefix = "master") : String
    instance_type_part = include_instance_type ? "#{instance_type}-" : ""
    "#{settings.cluster_name}-#{instance_type_part}#{prefix}#{index + 1}"
  end

  private def create_master_instance(index : Int32, placement_group : Hetzner::PlacementGroup?, location : String) : Hetzner::Instance::Create
    legacy_instance_type = masters_pool.legacy_instance_type
    instance_type = masters_pool.instance_type

    legacy_instance_name = build_instance_name(legacy_instance_type, index, true)
    instance_name = build_instance_name(instance_type, index, settings.include_instance_type_in_instance_name)

    image = masters_pool.image || settings.image
    additional_packages = masters_pool.additional_packages || settings.additional_packages
    additional_pre_k3s_commands = masters_pool.additional_pre_k3s_commands || settings.additional_pre_k3s_commands
    additional_post_k3s_commands = masters_pool.additional_post_k3s_commands || settings.additional_post_k3s_commands

    Hetzner::Instance::Create.new(
      settings: settings,
      hetzner_client: hetzner_client,
      mutex: mutex,
      legacy_instance_name: legacy_instance_name,
      instance_name: instance_name,
      instance_type: instance_type,
      image: image,
      ssh_key: ssh_key,
      network: network,
      placement_group: placement_group,
      additional_packages: additional_packages,
      additional_pre_k3s_commands: additional_pre_k3s_commands,
      additional_post_k3s_commands: additional_post_k3s_commands,
      location: location
    )
  end

  private def initialize_master_instances
    placement_group = create_placement_group_for_masters

    Array(Hetzner::Instance::Create).new(masters_pool.instance_count) do |i|
      create_master_instance(i, placement_group, masters_locations[i])
    end
  end

  private def create_worker_instance(index : Int32, node_pool, placement_group : Hetzner::PlacementGroup?) : Hetzner::Instance::Create
    legacy_instance_type = node_pool.legacy_instance_type
    instance_type = node_pool.instance_type

    legacy_instance_name = build_instance_name(legacy_instance_type, index, true, "pool-#{node_pool.name}-worker")
    instance_name = build_instance_name(instance_type, index, settings.include_instance_type_in_instance_name, "pool-#{node_pool.name}-worker")

    image = node_pool.image || settings.image
    additional_packages = node_pool.additional_packages || settings.additional_packages
    additional_pre_k3s_commands = node_pool.additional_pre_k3s_commands || settings.additional_pre_k3s_commands
    additional_post_k3s_commands = node_pool.additional_post_k3s_commands || settings.additional_post_k3s_commands

    Hetzner::Instance::Create.new(
      settings: settings,
      hetzner_client: hetzner_client,
      mutex: mutex,
      legacy_instance_name: legacy_instance_name,
      instance_name: instance_name,
      instance_type: instance_type,
      image: image,
      location: node_pool.location || default_masters_Location,
      ssh_key: ssh_key,
      network: network,
      placement_group: placement_group,
      additional_packages: additional_packages,
      additional_pre_k3s_commands: additional_pre_k3s_commands,
      additional_post_k3s_commands: additional_post_k3s_commands
    )
  end

  private def initialize_worker_instances
    factories = Array(Hetzner::Instance::Create).new
    static_worker_node_pools = settings.worker_node_pools.reject(&.autoscaling_enabled)

    create_placement_groups_for_worker_node_pools(static_worker_node_pools)

    static_worker_node_pools.each do |node_pool|
      node_pool_placement_groups = all_placement_groups.select { |pg| pg.name.includes?("#{settings.cluster_name}-#{node_pool.name}-") }
      node_pool.instance_count.times do |i|
        placement_group = node_pool_placement_groups[(i // MAX_INSTANCES_PER_PLACEMENT_GROUP) % node_pool_placement_groups.size]
        factories << create_worker_instance(i, node_pool, placement_group)
      end
    end

    factories
  end

  private def handle_created_instance(created_instance, kubernetes_installation_queue_channel, wait_channel, instance_factory, wait)
    if created_instance
      wait_channel.send(instance_factory) if wait
      instances << created_instance
      kubernetes_installation_queue_channel.send(created_instance)
    else
      puts "Instance creation for #{instance_factory.instance_name} failed. Try rerunning the create command."
    end
  end

  private def create_instances_concurrently(instance_factories, kubernetes_installation_queue_channel, wait = false)
    wait_channel = Channel(Hetzner::Instance::Create).new
    semaphore = Channel(Nil).new(10)

    instance_factories.each do |instance_factory|
      semaphore.send(nil)
      spawn do
        instance = nil
        begin
          created_instance = instance_factory.run
          semaphore.receive # release the semaphore immediately after instance creation
        rescue e : Exception
          puts "Error creating instance: #{e.message}"
        ensure
          handle_created_instance(created_instance, kubernetes_installation_queue_channel, wait_channel, instance_factory, wait)
        end
      end
    end

    instance_factories.size.times { wait_channel.receive } if wait
  end

  ### Placement groups

  private def find_placement_group_by_name(placement_group_name)
    all_placement_groups.find { |pg| pg.name == placement_group_name }
  end

  private def create_and_track_placement_group(placement_group_name)
    placement_group = Hetzner::PlacementGroup::Create.new(hetzner_client, placement_group_name).run

    track_placement_group(placement_group)
  end

  private def placement_group_exists?(placement_group_name)
    !find_placement_group_by_name(placement_group_name).nil?
  end

  private def track_placement_group(placement_group)
    mutex.synchronize do
      all_placement_groups << placement_group unless placement_group_exists?(placement_group.name)
    end

    placement_group
  end

  private def create_placement_group_for_masters
    placement_group_name = "#{settings.cluster_name}-masters"
    placement_group = find_placement_group_by_name(placement_group_name)
    placement_group ||= placement_group = Hetzner::PlacementGroup::Create.new(hetzner_client, placement_group_name).run

    track_placement_group(placement_group)
  end

  private def create_placement_groups_for_node_pool(node_pool, remaining_placement_groups, placement_groups_channel)
    created_placement_groups = 0
    placement_groups_count = [(node_pool.instance_count / MAX_INSTANCES_PER_PLACEMENT_GROUP).ceil.to_i, remaining_placement_groups].min
    pool_placement_groups = all_placement_groups.select { |pg| pg.name.includes?("#{settings.cluster_name}-#{node_pool.name}-") }
    new_placement_group_count = placement_groups_count - pool_placement_groups.size

    (pool_placement_groups.size..(pool_placement_groups.size + new_placement_group_count)).each do |index|
      next if index == 0

      placement_group_name = "#{settings.cluster_name}-#{node_pool.name}-#{index}"

      next if placement_group_exists?(placement_group_name)

      spawn do
        placement_group = create_and_track_placement_group(placement_group_name)
        placement_groups_channel.send(placement_group)
      end

      created_placement_groups += 1

      break if remaining_placement_groups - created_placement_groups <= 0
    end

    created_placement_groups
  end

  private def create_placement_groups_for_worker_node_pools(node_pools)
    node_pools = node_pools.sort_by(&.name.not_nil!)

    remaining_placement_groups = MAX_PLACEMENT_GROUPS - all_placement_groups.size
    placement_groups_channel = Channel(Hetzner::PlacementGroup).new
    created_placement_groups = 0

    node_pools.each do |node_pool|
      next if node_pool.instance_count <= 0

      created_placement_groups += create_placement_groups_for_node_pool(node_pool, remaining_placement_groups, placement_groups_channel)
      remaining_placement_groups -= created_placement_groups

      break if remaining_placement_groups <= 0
    end

    created_placement_groups.times { placement_groups_channel.receive }
  end

  private def delete_unused_placement_groups
    mutex.synchronize do
      @all_placement_groups = Hetzner::PlacementGroup::All.new(settings, hetzner_client).delete_unused
    end
  end

  ## Load balancer

  private def create_load_balancer
    @load_balancer = Hetzner::LoadBalancer::Create.new(
      settings: settings,
      hetzner_client: hetzner_client,
      location: default_masters_Location,
      network_id: network.try(&.id)
    ).run

    sleep 5.seconds
  end

  private def delete_load_balancer
    Hetzner::LoadBalancer::Delete.new(
      hetzner_client: hetzner_client,
      cluster_name: settings.cluster_name,
      print_log: false
    ).run
  end

  ## Private network

  private def find_existing_network(existing_network_name)
    Hetzner::Network::Find.new(hetzner_client, existing_network_name).run
  end

  private def create_new_network
    return unless settings.networking.private_network.enabled

    Hetzner::Network::Create.new(
      settings: settings,
      hetzner_client: hetzner_client,
      network_name: settings.cluster_name,
      network_zone: ::Configuration::Settings::NodePool::Location.network_zone_by_location(default_masters_Location)
    ).run
  end

  private def masters_locations
    masters_pool.locations
  end

  private def default_masters_Location
    masters_locations.first
  end

  private def find_or_create_network
    find_existing_network(settings.networking.private_network.existing_network_name) || create_new_network
  end

  ## Firewall

  private def configure_firewall
    Hetzner::Firewall::Create.new(
      settings: settings,
      hetzner_client: hetzner_client,
      firewall_name: settings.cluster_name,
      masters: instances.select(&.master?)
    ).run
  end

  ## SSH key

  private def create_ssh_key
    Hetzner::SSHKey::Create.new(
      hetzner_client: hetzner_client,
      settings: settings
    ).run
  end

  private def masters_pool
    settings.masters_pool
  end
end
