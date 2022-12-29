require "../../node_pool"
require "../../../hetzner/server_type"

class Configuration::Settings::NodePool::InstanceType
  getter errors : Array(String)
  getter pool : Configuration::NodePool
  getter server_types : Array(Hetzner::ServerType)

  def initialize(@errors, @pool, @server_types)
  end

  def validate
    return if pool && pool.instance_type && server_types.map(&.name).includes?(pool.instance_type)

    errors << "#{pool.name || "masters"} node pool has an invalid instance type"
  end
end
