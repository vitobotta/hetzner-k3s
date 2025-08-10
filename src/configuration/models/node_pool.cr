require "yaml"

require "./node_pool_config/label"
require "./node_pool_config/taint"
require "./node_pool_config/autoscaling"

abstract class Configuration::Models::NodePool
  include YAML::Serializable

  property name : String?
  property legacy_instance_type : String = ""
  property instance_type : String
  property image : String | Int64 | Nil
  property instance_count : Int32 = 1
  property labels : Array(::Configuration::Models::NodePoolConfig::Label) = [] of ::Configuration::Models::NodePoolConfig::Label
  property taints : Array(::Configuration::Models::NodePoolConfig::Taint) = [] of ::Configuration::Models::NodePoolConfig::Taint
  property autoscaling : ::Configuration::Models::NodePoolConfig::Autoscaling?
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
