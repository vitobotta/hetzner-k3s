require "../../node_pool"

class Configuration::Settings::NodePool::InstanceCount
  getter errors : Array(String)
  getter pool : Configuration::NodePool
  getter pool_type : Symbol

  def initialize(@errors, @pool, @pool_type)
  end

  def validate
    validate_master_count if pool_type == :masters
  end

  private def validate_master_count
    if pool.instance_count > 0 && (pool.instance_count == 1 || pool.instance_count.odd?)
      return
    else
      errors << "Masters count must equal to 1 for non-HA clusters or an odd number (recommended 3) for an HA cluster"
    end
  end
end
