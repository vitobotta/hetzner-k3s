require "../../models/node_pool"
require "../cluster/datastore"

class Configuration::Validators::Nodes::InstanceCount
  getter errors : Array(String)
  getter pool : Configuration::Models::MasterNodePool | Configuration::Models::WorkerNodePool
  getter pool_type : Symbol
  getter datastore : Configuration::Models::Datastore

  def initialize(@errors, @pool, @pool_type, @datastore)
  end

  def validate
    return unless pool_type == :masters
    return errors << "Masters count must equal to 1 for non-HA clusters or an odd number (recommended 3) for an HA cluster" unless pool.instance_count > 0 && (pool.instance_count.odd? || datastore.mode == "external")
  end
end
