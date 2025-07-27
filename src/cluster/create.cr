require "../configuration/main"
require "../configuration/loader"
require "../hetzner/client"
require "../hetzner/ssh_key/create"
require "../util/ssh"
require "../kubernetes/installer"
require "./placement_group_manager"
require "./instance_builder"
require "./network_manager"
require "./load_balancer_manager"

class Cluster::Create
  private getter configuration : Configuration::Loader
  private getter hetzner_client : Hetzner::Client { configuration.hetzner_client }
  private getter settings : Configuration::Main { configuration.settings }
  private getter autoscaling_worker_node_pools : Array(Configuration::WorkerNodePool) { settings.worker_node_pools.select(&.autoscaling_enabled) }
  private getter ssh_client : Util::SSH { Util::SSH.new(settings.networking.ssh.private_key_path, settings.networking.ssh.public_key_path) }
  private getter network : Hetzner::Network?
  private getter ssh_key : Hetzner::SSHKey
  private getter load_balancer : Hetzner::LoadBalancer?
  private getter instances : Array(Hetzner::Instance) = [] of Hetzner::Instance
  private getter master_instances : Array(Hetzner::Instance::Create)
  private getter worker_instances : Array(Hetzner::Instance::Create)

  private property kubernetes_masters_installation_queue_channel do
    Channel(Hetzner::Instance).new(5)
  end
  private property kubernetes_workers_installation_queue_channel do
    Channel(Hetzner::Instance).new(10)
  end
  private property completed_channel : Channel(Nil) = Channel(Nil).new
  private property mutex : Mutex = Mutex.new

  private getter placement_group_manager : PlacementGroupManager
  private getter instance_builder : InstanceBuilder
  private getter network_manager : NetworkManager
  private getter load_balancer_manager : LoadBalancerManager

  def initialize(@configuration)
    existing_placement_groups = Hetzner::PlacementGroup::All.new(settings, hetzner_client).run
    @placement_group_manager = PlacementGroupManager.new(settings, hetzner_client, mutex, existing_placement_groups)
    @network_manager = NetworkManager.new(settings, hetzner_client)
    @load_balancer_manager = LoadBalancerManager.new(settings, hetzner_client)

    @network = network_manager.find_or_create if settings.networking.private_network.enabled
    @ssh_key = create_ssh_key
    @instance_builder = InstanceBuilder.new(settings, hetzner_client, mutex, ssh_key, network)
    placement_group_manager.delete_unused
    @master_instances = instance_builder.initialize_master_instances(masters_locations, placement_group_manager.create_for_masters)

    static_worker_node_pools = settings.worker_node_pools.reject(&.autoscaling_enabled)
    placement_group_manager.create_for_worker_node_pools(static_worker_node_pools)
    @worker_instances = create_worker_instances_with_placement_groups(static_worker_node_pools)
  end

  def run
    create_instances_concurrently(master_instances, kubernetes_masters_installation_queue_channel, wait: true)

    load_balancer_manager.handle(master_instances.size, network)

    initiate_k3s_setup

    create_instances_concurrently(worker_instances, kubernetes_workers_installation_queue_channel)

    completed_channel.receive

    placement_group_manager.delete_unused

    warn_if_not_protected
  end


  private def create_ssh_key
    Hetzner::SSHKey::Create.new(hetzner_client, settings).run
  end

  private def warn_if_not_protected
    return if settings.protect_against_deletion

    puts
    puts "WARNING!!! The cluster is not protected against deletion. If you want to protect the cluster against deletion, set `protect_against_deletion: true` in the configuration file.".colorize(:yellow)
    puts
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

  ### Instances

  private def masters_locations : Array(String)
    settings.masters_pool.locations
  end

  private def create_worker_instances_with_placement_groups(node_pools) : Array(Hetzner::Instance::Create)
    factories = Array(Hetzner::Instance::Create).new

    node_pools.each do |node_pool|
      node_pool_placement_groups = placement_group_manager.all_placement_groups.select { |pg| pg.name.includes?("#{settings.cluster_name}-#{node_pool.name}-") }

      # Ensure we have placement groups for this pool
      if node_pool_placement_groups.empty?
        static_worker_node_pools = [node_pool]
        placement_group_manager.create_for_worker_node_pools(static_worker_node_pools)
        node_pool_placement_groups = placement_group_manager.all_placement_groups.select { |pg| pg.name.includes?("#{settings.cluster_name}-#{node_pool.name}-") }
      end

      # Use synchronized placement group assignment with round-robin
      node_pool.instance_count.times do |i|
        placement_group = placement_group_manager.assign_placement_group(node_pool_placement_groups, i)
        factories << instance_builder.create_worker_instance(i, node_pool, placement_group)
      end
    end

    factories
  end

  private def handle_created_instance(created_instance, kubernetes_installation_queue_channel, wait_channel, instance_factory, wait)
    return unless created_instance

    wait_channel.send(instance_factory) if wait
    instances << created_instance
    kubernetes_installation_queue_channel.send(created_instance)
  end

  private def create_instances_concurrently(instance_factories, kubernetes_installation_queue_channel, wait = false)
    wait_channel = Channel(Hetzner::Instance::Create).new
    semaphore = Channel(Nil).new(10)

    instance_factories.each do |instance_factory|
      semaphore.send(nil)
      spawn do
        begin
          created_instance = instance_factory.run
          semaphore.receive # release the semaphore immediately after instance creation
          handle_created_instance(created_instance, kubernetes_installation_queue_channel, wait_channel, instance_factory, wait)
        rescue e : Exception
          puts "Error creating instance: #{e.message}"
        end
      end
    end

    instance_factories.size.times { wait_channel.receive } if wait
  end
end
