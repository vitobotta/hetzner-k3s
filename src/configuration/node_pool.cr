require "yaml"

require "./node_label"
require "./node_taint"
require "./autoscaling"

class Configuration::NodePool
  include YAML::Serializable

  property name : String?
  property instance_type : String
  property location : String
  property image : String | Int64 | Nil
  property instance_count : Int32 = 1
  property labels : Array(::Configuration::NodeLabel) = [] of ::Configuration::NodeLabel
  property taints : Array(::Configuration::NodeTaint) = [] of ::Configuration::NodeTaint
  property autoscaling : ::Configuration::Autoscaling?
  property post_create_commands : Array(String) | Nil
  property additional_packages : Array(String) | Nil

  getter autoscaling_enabled : Bool do
    autoscaling.try(&.enabled) || false
  end
end
