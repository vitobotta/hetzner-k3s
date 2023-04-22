require "../../node_pool"
require "../../../hetzner/server_type"

class Configuration::Settings::NodePool::InstanceType
  getter errors : Array(String)
  getter pool : Configuration::NodePool
  getter server_types : Array(Hetzner::ServerType)

  def initialize(@errors, @pool, @server_types)
  end

  def validate
    return if valid_instance_type?

    errors << "#{pool.name || "masters"} node pool has an invalid instance type"
  end

  private def valid_instance_type?
    server_types.any? { |server_type| server_type.name == pool.instance_type }
  end
end
