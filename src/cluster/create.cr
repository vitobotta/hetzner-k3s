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
require "../util/ssh"

class Cluster::Create
  MAX_PLACEMENT_GROUPS = 50
  MAX_INSTANCES_PER_PLACEMENT_GROUP = 10 # Assuming this is the maximum number of instances per placement group

  private getter configuration : Configuration::Loader
  private getter hetzner_client : Hetzner::Client do
    configuration.hetzner_client
  end
  private getter settings : Configuration::Main do
    configuration.settings
  end
  private getter autoscaling_worker_node_pools : Array(Configuration::NodePool) do
    settings.worker_node_pools.select(&.autoscaling_enabled)
  end
  private getter ssh_client : Util::SSH do
    Util::SSH.new(settings.networking.ssh.private_key_path, settings.networking.ssh.public_key_path)
  end

  private getter network : Hetzner::Network?
  private getter ssh_key : Hetzner::SSHKey
  private getter load_balancer : Hetzner::LoadBalancer?
  private getter placement_groups : Hash(String, Hetzner::PlacementGroup?) = Hash(String, Hetzner::PlacementGroup?).new
  private property instances : Array(Hetzner::Instance) = [] of Hetzner::Instance

  private getter master_instance_creators : Array(Hetzner::Instance::Create)
  private getter worker_instance_creators : Array(Hetzner::Instance::Create)

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
    @all_placement_groups = Hetzner::PlacementGroup::All.new(hetzner_client).delete_unused
    @master_instance_creators = initialize_master_instance_creators
    @worker_instance_creators = initialize_worker_instance_creators
  end

  def run
    create_instances_concurrently(master_instance_creators, kubernetes_masters_installation_queue_channel, wait: true)

    configure_firewall
    # create_load_balancer if master_instance_creators.size > 1

    kubernetes_installer = Kubernetes::Installer.new(
      configuration,
      # load_balancer,
      ssh_client,
      autoscaling_worker_node_pools
    )

    spawn do
      kubernetes_installer.run(
        masters_installation_queue_channel: kubernetes_masters_installation_queue_channel,
        workers_installation_queue_channel: kubernetes_workers_installation_queue_channel,
        completed_channel: completed_channel,
        master_count: master_instance_creators.size,
        worker_count: worker_instance_creators.size
      )
    end

    create_instances_concurrently(worker_instance_creators, kubernetes_workers_installation_queue_channel)

    completed_channel.receive

    delete_unused_placement_groups
  end

  private def initialize_master_instance_creators
    creators = Array(Hetzner::Instance::Create).new

    masters_pool = settings.masters_pool
    placement_group = create_placement_group_for_masters

    masters_pool.instance_count.times do |i|
      creators << create_master_instance(i, placement_group)
    end

    creators
  end

  private def create_placement_group_for_masters
    placement_group_name = "#{settings.cluster_name}-masters"

    placement_group = all_placement_groups.find { |pg| pg.name == placement_group_name }

    unless placement_group
      placement_group = Hetzner::PlacementGroup::Create.new(
        hetzner_client: hetzner_client,
        placement_group_name: placement_group_name
      ).run

      track_placement_group(placement_group)
    end

    placement_group
  end

  private def track_placement_group(placement_group)
    mutex.synchronize do
      unless all_placement_groups.any? { |pg| pg.name == placement_group.name }
        all_placement_groups << placement_group
      end
    end
  end

  private def create_master_instance(index : Int32, placement_group : Hetzner::PlacementGroup?) : Hetzner::Instance::Create
    instance_type = settings.masters_pool.instance_type

    master_name = if settings.include_instance_type_in_instance_name
      "#{settings.cluster_name}-#{instance_type}-master#{index + 1}"
    else
      "#{settings.cluster_name}-master#{index + 1}"
    end

    image = settings.masters_pool.image || settings.image
    additional_packages = settings.masters_pool.additional_packages || settings.additional_packages
    additional_post_create_commands = settings.masters_pool.post_create_commands || settings.post_create_commands

    Hetzner::Instance::Create.new(
      settings: settings,
      hetzner_client: hetzner_client,
      mutex: mutex,
      instance_name: master_name,
      instance_type: instance_type,
      image: image,
      ssh_key: ssh_key,
      network: network,
      placement_group: placement_group,
      additional_packages: additional_packages,
      additional_post_create_commands: additional_post_create_commands
    )
  end

  private def initialize_worker_instance_creators
    creators = Array(Hetzner::Instance::Create).new
    no_autoscaling_worker_node_pools = settings.worker_node_pools.reject(&.autoscaling_enabled)

    create_placement_groups_for_worker_node_pools(no_autoscaling_worker_node_pools)

    no_autoscaling_worker_node_pools.each do |node_pool|
      node_pool_placement_groups = all_placement_groups.select { |pg| pg.name.includes?("#{settings.cluster_name}-#{node_pool.name}-") }
      node_pool.instance_count.times do |i|
        placement_group = node_pool_placement_groups[(i // MAX_INSTANCES_PER_PLACEMENT_GROUP) % node_pool_placement_groups.size]
        creators << create_worker_instance(i, node_pool, placement_group)
      end
    end

    creators
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
      @all_placement_groups = Hetzner::PlacementGroup::All.new(hetzner_client).delete_unused
    end
  end

  private def create_placement_groups_for_node_pool(node_pool, remaining_placement_groups, placement_groups_channel)
    placement_groups_count = (node_pool.instance_count / MAX_INSTANCES_PER_PLACEMENT_GROUP).ceil.to_i
    placement_groups_count = [placement_groups_count, remaining_placement_groups].min
    created_placement_groups = 0

    ((all_placement_groups.size + 1)..(all_placement_groups.size + placement_groups_count)).each do |index|
      placement_group_name = "#{settings.cluster_name}-#{node_pool.name}-#{index}"

      next if all_placement_groups.any? { |pg| pg.name == placement_group_name }

      spawn do
        placement_group = Hetzner::PlacementGroup::Create.new(
          hetzner_client: hetzner_client,
          placement_group_name: placement_group_name
        ).run

        track_placement_group(placement_group)
        placement_groups_channel.send(placement_group)
      end

      created_placement_groups += 1
      break if remaining_placement_groups - created_placement_groups <= 0
    end

    created_placement_groups
  end

  private def create_worker_instance(index : Int32, node_pool, placement_group : Hetzner::PlacementGroup?) : Hetzner::Instance::Create
    instance_type = node_pool.instance_type

    node_name = if settings.include_instance_type_in_instance_name
      "#{settings.cluster_name}-#{instance_type}-pool-#{node_pool.name}-worker#{index + 1}"
    else
      "#{settings.cluster_name}-pool-#{node_pool.name}-worker#{index + 1}"
    end

    image = node_pool.image || settings.image
    additional_packages = node_pool.additional_packages || settings.additional_packages
    additional_post_create_commands = node_pool.post_create_commands || settings.post_create_commands

    Hetzner::Instance::Create.new(
      settings: settings,
      hetzner_client: hetzner_client,
      mutex: mutex,
      instance_name: node_name,
      instance_type: instance_type,
      image: image,
      location: node_pool.location,
      ssh_key: ssh_key,
      network: network,
      placement_group: placement_group,
      additional_packages: additional_packages,
      additional_post_create_commands: additional_post_create_commands
    )
  end

  private def create_load_balancer
    @load_balancer = Hetzner::LoadBalancer::Create.new(
      settings: settings,
      hetzner_client: hetzner_client,
      location: configuration.masters_location,
      network_id: network.try(&.id)
    ).run
  end

  private def create_instances_concurrently(instance_creators, kubernetes_installation_queue_channel, wait = false)
    wait_channel = Channel(Hetzner::Instance::Create).new
    semaphore = Channel(Nil).new(50)

    instance_creators.each do |instance_creator|
      semaphore.send(nil)
      spawn do
        instance = nil
        begin
          Retriable.retry(max_attempts: 3, on: Tasker::Timeout, backoff: false) do
            Tasker.timeout(settings.timeouts.instance_creation_timeout.seconds) do
              instance = instance_creator.run
            end
          end

          semaphore.receive # release the semaphore immediately after instance creation
        rescue e : Exception
          puts "Error creating instance: #{e.message}"
        ensure
          created_instance = instance

          if created_instance
            mutex.synchronize { instances << created_instance }
            wait_channel = wait_channel.send(instance_creator) if wait
            kubernetes_installation_queue_channel.send(created_instance)
          else
            puts "Instance creation for #{instance_creator.instance_name} failed. Try rerunning the create command."
          end
        end
      end
    end

    return unless wait

    instance_creators.size.times do |instance_creator|
      wait_channel.receive
    end
  end

  private def find_network
    existing_network_name = settings.networking.private_network.existing_network_name

    return find_existing_network(existing_network_name) if existing_network_name
    create_new_network
  end

  private def find_existing_network(existing_network_name)
    Hetzner::Network::Find.new(hetzner_client, existing_network_name).run
  end

  private def create_new_network
    return unless settings.networking.private_network.enabled

    Hetzner::Network::Create.new(
      settings: settings,
      hetzner_client: hetzner_client,
      network_name: settings.cluster_name,
      locations: configuration.locations
    ).run
  end

  private def find_or_create_network
    find_network || create_new_network
  end

  private def configure_firewall
    Hetzner::Firewall::Create.new(
      settings: settings,
      hetzner_client: hetzner_client,
      firewall_name: settings.cluster_name,
      masters: masters
    ).run
  end

  private def create_ssh_key
    Hetzner::SSHKey::Create.new(
      hetzner_client: hetzner_client,
      settings: settings
    ).run
  end

  private def default_log_prefix
    "Cluster create"
  end

  private def masters
    instances.select { |instance| instance.master? }.sort_by(&.name)
  end

  private def workers
    instances.select { |instance| instance.master? }.sort_by(&.name)
  end
end
