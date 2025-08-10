require "../../models/node_pool"
require "../../../hetzner/instance_type"

class Configuration::Validators::Nodes::InstanceType
  getter errors : Array(String)
  getter pool : Configuration::MasterNodePool | Configuration::WorkerNodePool
  getter instances_types : Array(Hetzner::InstanceType)

  def initialize(@errors, @pool, @instances_types)
  end

  def validate
    return if valid_instance_type?

    errors << "#{pool.name || "masters"} node pool has an invalid instance type"
  end

  private def valid_instance_type?
    instances_types.any? { |instance_type| instance_type.name == pool.instance_type }
  end
end
