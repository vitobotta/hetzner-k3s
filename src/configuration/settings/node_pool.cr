require "../../hetzner/location"
require "../../hetzner/server_type"
require "../node_pool"

class Configuration::Settings::NodePool
  getter errors : Array(String) = [] of String
  getter pool : Configuration::NodePool?
  getter pool_type : Symbol = :workers
  getter masters_location : String?
  getter server_types : Array(Hetzner::ServerType) = [] of Hetzner::ServerType
  getter locations : Array(Hetzner::Location) = [] of Hetzner::Location

  getter pool_name : String do
    if masters?
      "masters"
    else
      pool.try(&.name) || "<unnamed-pool>"
    end
  end

  getter pool_description do
     workers ? "Worker mode pool '#{pool_name}'" : "Masters pool"
  end

  def initialize(
      @errors,
      @pool,
      @pool_type,
      @masters_location,
      @server_types,
      @locations
    )
  end

  def validate
    given_pool = pool
    given_pool_type = pool_type

    return unless given_pool

    PoolName.new(errors, given_pool_type, pool_name).validate
    InstanceType.new(errors, given_pool, server_types).validate
    Location.new(errors, given_pool, given_pool_type, masters_location, locations).validate
    InstanceCount.new(errors, given_pool, given_pool_type).validate
    NodeLabels.new(errors, given_pool_type, given_pool.try(&.labels)).validate
    NodeTaints.new(errors, given_pool_type, given_pool.try(&.taints)).validate
    Autoscaling.new(errors, given_pool).validate if given_pool_type == :workers
  end

  private def workers?
    pool_type == :workers
  end

  private def masters?
    pool_type == :masters
  end
end

