require "./node_pool"

class Configuration::Models::WorkerNodePool < Configuration::Models::NodePool
  property location : String = "fsn1"
end
