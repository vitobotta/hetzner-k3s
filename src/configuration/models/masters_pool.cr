require "./node_pool"

class Configuration::MasterNodePool < Configuration::NodePool
  property locations : Array(String) = ["fsn1"] of String
end
