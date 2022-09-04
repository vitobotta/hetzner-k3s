require "yaml"

require "./node_label"
require "./node_taint"

class Configuration::NodePool
  include YAML::Serializable

  property name : String?
  property instance_type : String?
  property location : String?
  property instance_count : Int32?
  property labels : Array(::Configuration::NodeLabel)?
  property taints : Array(::Configuration::NodeTaint)?
end
