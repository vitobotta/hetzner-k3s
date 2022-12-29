require "../../node_pool"

class Configuration::Settings::NodePool::InstanceCount
  getter errors : Array(String)
  getter pool : Configuration::NodePool
  getter pool_type : Symbol

  def initialize(@errors, @pool, @pool_type)
  end

  def validate
    instance_count = pool.try(&.instance_count)

    return unless instance_count

    if instance_count < 1
      errors << "#{pool_type} must have at least one node"
    elsif instance_count > 10
      errors << "#{pool_type} cannot have more than 10 nodes due to a limitation with the Hetzner placement pools. You can add more node pools if you need more nodes."
    elsif pool_type == :masters && instance_count.even?
      errors << "Masters count must equal to 1 for non-HA clusters or an odd number (recommended 3) for an HA cluster"
    end
  end
end
