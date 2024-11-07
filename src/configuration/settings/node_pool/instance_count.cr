require "../../node_pool"
require "../../datastore"

class Configuration::Settings::NodePool::InstanceCount
  getter errors : Array(String)
  getter pool : Configuration::NodePool
  getter pool_type : Symbol
  getter datastore : Configuration::Datastore::Config

  def initialize(@errors, @pool, @pool_type, @datastore)
  end

  def validate
    validate_master_count if pool_type == :masters
  end

  private def validate_master_count
    if pool.instance_count > 0 && (pool.instance_count.odd? || datastore.mode == "external")
      return
    else
      errors << "Masters count must equal to 1 for non-HA clusters or an odd number (recommended 3) for an HA cluster"
    end
  end
end
