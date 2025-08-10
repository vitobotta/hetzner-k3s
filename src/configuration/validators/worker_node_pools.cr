require "../models/worker_node_pool"
require "../models/master_node_pool"
require "../models/datastore"
require "../../hetzner/instance_type"
require "../../hetzner/location"
require "./node_pool"

class Configuration::Validators::WorkerNodePools
  getter errors : Array(String) = [] of String
  getter worker_node_pools : Array(Configuration::Models::WorkerNodePool)
  getter schedule_workloads_on_masters : Bool
  getter masters_pool : Configuration::Models::MasterNodePool
  getter instance_types : Array(Hetzner::InstanceType)
  getter all_locations : Array(Hetzner::Location)
  getter datastore : Configuration::Models::Datastore
  getter private_network_enabled : Bool

  def initialize(
    @errors,
    @worker_node_pools,
    @schedule_workloads_on_masters,
    @masters_pool,
    @instance_types,
    @all_locations,
    @datastore,
    @private_network_enabled
  )
  end

  def validate
    if worker_node_pools.empty? && !schedule_workloads_on_masters
      errors << "At least one worker node pool is required in order to schedule workloads"
      return
    end

    names = worker_node_pools.map(&.name)
    errors << "Each worker node pool must have a unique name" if names.uniq.size != names.size

    worker_node_pools.each do |pool|
      Configuration::Validators::NodePool.new(
        errors: errors,
        pool: pool,
        pool_type: :workers,
        masters_pool: masters_pool,
        instance_types: instance_types,
        all_locations: all_locations,
        datastore: datastore,
        private_network_enabled: private_network_enabled
      ).validate
    end
  end
end