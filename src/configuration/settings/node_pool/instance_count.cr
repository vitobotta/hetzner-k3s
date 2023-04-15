require "../../node_pool"

class Configuration::Settings::NodePool::InstanceCount
  getter errors : Array(String)
  getter pool : Configuration::NodePool
  getter pool_type : Symbol

  def initialize(@errors, @pool, @pool_type)
  end

  def validate
    instance_count = pool.instance_count

    min_count, max_count = 1, 10

    if (min_count..max_count).includes?(instance_count)
      validate_master_count if pool_type == :masters
    else
      errors << "#{pool_type} must have between #{min_count} and #{max_count} nodes due to a limitation with the Hetzner placement pools. You can add more node pools if you need more nodes."
    end
  end

  private def validate_master_count
    if pool.instance_count == 1 || pool.instance_count.odd?
      return
    else
      errors << "Masters count must equal to 1 for non-HA clusters or an odd number (recommended 3) for an HA cluster"
    end
  end
end
