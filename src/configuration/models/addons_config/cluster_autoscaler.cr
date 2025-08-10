require "yaml"

class Configuration::ClusterAutoscaler
  include YAML::Serializable

  property scan_interval : String = "10s"
  property scale_down_delay_after_add : String = "10m"
  property scale_down_delay_after_delete : String = "10s"
  property scale_down_delay_after_failure : String = "3m"
  property max_node_provision_time : String = "15m"

  def initialize
  end

  def initialize(pull : YAML::PullParser)
    previous_def(pull)
  end
end
