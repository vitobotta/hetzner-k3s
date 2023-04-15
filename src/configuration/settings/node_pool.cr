require "../../hetzner/location"
require "../../hetzner/server_type"
require "../node_pool"

class Configuration::Settings::NodePool
  getter errors : Array(String) = [] of String
  getter pool : Configuration::NodePool
  getter pool_type : Symbol = :workers
  getter masters_location : String?
  getter server_types : Array(Hetzner::ServerType) = [] of Hetzner::ServerType
  getter locations : Array(Hetzner::Location) = [] of Hetzner::Location

  getter pool_name : String { masters? ? "masters" : pool.try(&.name) || "<unnamed-pool>" }
  getter pool_description : String { workers? ? "Worker mode pool '#{pool_name}'" : "Masters pool" }

  def initialize(@errors, @pool, @pool_type, @masters_location, @server_types, @locations)
  end

  def validate
    return unless pool

    PoolName.new(errors, pool_type, pool_name).validate
    InstanceType.new(errors, pool, server_types).validate
    Location.new(errors, pool, pool_type, masters_location, locations).validate
    InstanceCount.new(errors, pool, pool_type).validate unless pool.autoscaling_enabled
    NodeLabels.new(errors, pool_type, pool.try(&.labels)).validate
    NodeTaints.new(errors, pool_type, pool.try(&.taints)).validate
    Autoscaling.new(errors, pool).validate if pool_type == :workers
  end

  private def workers?
    pool_type == :workers
  end

  private def masters?
    pool_type == :masters
  end
end
