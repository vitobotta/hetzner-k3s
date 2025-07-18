require "yaml"

class Configuration::Autoscaling
  include YAML::Serializable

  property enabled : Bool = false
  property min_instances : Int32 = 0
  property max_instances : Int32 = 0
  
  # Autoscaler configuration parameters with defaults
  property scan_interval : String = "10s"
  property scale_down_delay_after_add : String = "10m"
  property scale_down_delay_after_delete : String = "10s"
  property scale_down_delay_after_failure : String = "3m"
  property max_node_provision_time : String = "15m"
end
