require "yaml"

require "./label"
require "./taint"
require "./autoscaling"

abstract class Configuration::NodePool
  include YAML::Serializable

  property name : String?
  property legacy_instance_type : String = ""
  property instance_type : String
  property image : String | Int64 | Nil
  property instance_count : Int32 = 1
  property labels : Array(::Configuration::Label) = [] of ::Configuration::Label
  property taints : Array(::Configuration::Taint) = [] of ::Configuration::Taint
  property autoscaling : ::Configuration::Autoscaling?
  property additional_pre_k3s_commands : Array(String) | Nil
  property additional_post_k3s_commands : Array(String) | Nil
  property additional_packages : Array(String) | Nil
  property include_cluster_name_as_prefix : Bool = true
  property grow_root_partition_automatically : Bool? = nil

  getter autoscaling_enabled : Bool do
    autoscaling.try(&.enabled) || false
  end

  # Returns the effective value for grow_root_partition_automatically
  # Falls back to global setting if not set on the pool
  def effective_grow_root_partition_automatically(global_value : Bool) : Bool
    grow_root_partition_automatically.nil? ? global_value : grow_root_partition_automatically.not_nil!
  end
end
