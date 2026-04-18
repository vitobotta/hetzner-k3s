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

  # Manifest URL and image tag moved from global manifests block
  property manifest_url : String = "https://raw.githubusercontent.com/kubernetes/autoscaler/master/cluster-autoscaler/cloudprovider/hetzner/examples/cluster-autoscaler-run-on-master.yaml"
  property container_image_tag : String = "v1.35.0"

  def initialize(@enabled : Bool = true)
  end

  def enabled?
    enabled
  end
end
