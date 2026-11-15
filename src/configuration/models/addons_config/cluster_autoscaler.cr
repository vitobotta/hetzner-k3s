require "yaml"

class Configuration::Models::AddonsConfig::ClusterAutoscaler
  include YAML::Serializable
  include YAML::Serializable::Unmapped

  # Whether the Cluster Autoscaler addon is enabled.
  getter enabled : Bool

  property scan_interval : String = "10s"
  property scale_down_delay_after_add : String = "10m"
  property scale_down_delay_after_delete : String = "10s"
  property scale_down_delay_after_failure : String = "3m"
  property max_node_provision_time : String = "15m"

  # Nil means the manifest vendored under templates/, so an upstream change cannot break a run.
  property manifest_url : String? = nil
  property local_manifest_path : String? = nil
  property container_image_tag : String = "v1.34.3"

  def initialize(@enabled : Bool = true)
  end

  def enabled?
    enabled
  end
end
