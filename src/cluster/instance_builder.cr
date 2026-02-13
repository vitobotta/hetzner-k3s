require "../hetzner/instance/create"

class Cluster::InstanceBuilder
  private getter settings : Configuration::Main
  private getter hetzner_client : Hetzner::Client
  private getter mutex : Mutex
  private getter ssh_key : Hetzner::SSHKey
  private getter network : Hetzner::Network?

  def initialize(@settings, @hetzner_client, @mutex, @ssh_key, @network)
  end

  def build_instance_name(instance_type, index, include_instance_type, prefix = "master") : String
    instance_type_part = include_instance_type ? "#{instance_type}-" : ""
    "#{settings.cluster_name}-#{instance_type_part}#{prefix}#{index + 1}"
  end

  def create_master_instance(index : Int32, location : String) : Hetzner::Instance::Create
    masters_pool = settings.masters_pool
    legacy_instance_type = masters_pool.legacy_instance_type
    instance_type = masters_pool.instance_type

    legacy_instance_name = build_instance_name(legacy_instance_type, index, true)
    instance_name = build_instance_name(instance_type, index, settings.include_instance_type_in_instance_name)

    image = masters_pool.image || settings.image
    additional_packages = masters_pool.additional_packages || settings.additional_packages
    additional_pre_k3s_commands = masters_pool.additional_pre_k3s_commands || settings.additional_pre_k3s_commands
    grow_root_partition_automatically = masters_pool.effective_grow_root_partition_automatically(settings.grow_root_partition_automatically)

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
      additional_packages: additional_packages,
      additional_pre_k3s_commands: additional_pre_k3s_commands,
      location: location,
      grow_root_partition_automatically: grow_root_partition_automatically
    )
  end

  def create_worker_instance(index : Int32, node_pool) : Hetzner::Instance::Create
    legacy_instance_type = node_pool.legacy_instance_type
    instance_type = node_pool.instance_type

    legacy_instance_name = build_instance_name(legacy_instance_type, index, true, "pool-#{node_pool.name}-worker")
    instance_name = build_instance_name(instance_type, index, settings.include_instance_type_in_instance_name, "pool-#{node_pool.name}-worker")

    image = node_pool.image || settings.image
    additional_packages = node_pool.additional_packages || settings.additional_packages
    additional_pre_k3s_commands = node_pool.additional_pre_k3s_commands || settings.additional_pre_k3s_commands
    grow_root_partition_automatically = node_pool.effective_grow_root_partition_automatically(settings.grow_root_partition_automatically)

    Hetzner::Instance::Create.new(
      settings: settings,
      hetzner_client: hetzner_client,
      mutex: mutex,
      legacy_instance_name: legacy_instance_name,
      instance_name: instance_name,
      instance_type: instance_type,
      image: image,
      location: node_pool.location || default_masters_location,
      ssh_key: ssh_key,
      network: network,
      additional_packages: additional_packages,
      additional_pre_k3s_commands: additional_pre_k3s_commands,
      grow_root_partition_automatically: grow_root_partition_automatically
    )
  end

  def initialize_master_instances(masters_locations) : Array(Hetzner::Instance::Create)
    Array(Hetzner::Instance::Create).new(settings.masters_pool.instance_count) do |i|
      create_master_instance(i, masters_locations[i])
    end
  end

  def initialize_worker_instances : Array(Hetzner::Instance::Create)
    factories = Array(Hetzner::Instance::Create).new
    static_worker_node_pools = settings.worker_node_pools.reject(&.autoscaling_enabled)

    static_worker_node_pools.each do |node_pool|
      node_pool.instance_count.times do |i|
        factories << create_worker_instance(i, node_pool)
      end
    end

    factories
  end

  private def default_masters_location
    settings.masters_pool.locations.first
  end
end
