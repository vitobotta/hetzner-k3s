require "yaml"

require "./node_label"
require "./node_taint"

class Configuration::NodePool
  include YAML::Serializable

  property name : String?
  property instance_type : String
  property location : String
  property instance_count : Int32 = 1
  property labels : Array(::Configuration::NodeLabel) = [] of ::Configuration::NodeLabel
  property taints : Array(::Configuration::NodeTaint) = [] of ::Configuration::NodeTaint
end
