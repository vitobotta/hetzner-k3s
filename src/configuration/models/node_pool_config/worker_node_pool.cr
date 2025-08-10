require "../node_pool"

class Configuration::WorkerNodePool < Configuration::NodePool
  property location : String = "fsn1"
end
