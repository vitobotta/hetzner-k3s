require "../../../hetzner/location"
require "../../../hetzner/instance_type"
require "../../models/node_pool"
require "../cluster/datastore"

class Configuration::Validators::Nodes::NodePool
  getter errors : Array(String) = [] of String
  getter pool : Configuration::Models::MasterNodePool | Configuration::Models::WorkerNodePool
  getter pool_type : Symbol = :workers
  getter masters_pool : Configuration::Models::MasterNodePool
  getter instance_types : Array(Hetzner::InstanceType) = [] of Hetzner::InstanceType
  getter all_locations : Array(Hetzner::Location) = [] of Hetzner::Location

  getter pool_name : String { masters? ? "masters" : pool.try(&.name) || "<unnamed-pool>" }
  getter pool_description : String { workers? ? "Worker mode pool '#{pool_name}'" : "Masters pool" }

  getter datastore : Configuration::Models::Datastore

  def initialize(@errors, @pool, @pool_type, @masters_pool, @instance_types, @all_locations, @datastore)
  end

  def validate
    return unless pool

    Configuration::Validators::Nodes::PoolName.new(errors, pool_type, pool_name).validate
    Configuration::Validators::Nodes::InstanceType.new(errors, pool, instance_types).validate
    Configuration::Validators::Nodes::Location.new(errors, pool, pool_type, masters_pool, all_locations).validate
    Configuration::Validators::Nodes::InstanceCount.new(errors, pool, pool_type, datastore).validate unless pool.autoscaling_enabled
    Configuration::Validators::Nodes::NodeLabels.new(errors, pool_type, pool.try(&.labels)).validate
    Configuration::Validators::Nodes::NodeTaints.new(errors, pool_type, pool.try(&.taints)).validate
    Configuration::Validators::Nodes::Autoscaling.new(errors, pool).validate if workers?
  end

  private def workers?
    pool_type == :workers
  end

  private def masters?
    pool_type == :masters
  end
end
