require "./node_pool"

class Configuration::Models::MasterNodePool < Configuration::Models::NodePool
  property locations : Array(String) = ["fsn1"] of String
end
