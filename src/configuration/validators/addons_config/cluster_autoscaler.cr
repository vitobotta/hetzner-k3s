require "../../models/addons_config/cluster_autoscaler"

# The autoscaler takes these as Go durations. A typo does not fail the run, it crash-loops the
# autoscaler pod, which stops all scaling, so they are checked here instead.
class Configuration::Validators::AddonsConfig::ClusterAutoscaler
  DURATION = /\A(\d+(\.\d+)?(ns|us|µs|ms|s|m|h))+\z/

  getter errors : Array(String)
  getter cluster_autoscaler : Configuration::Models::AddonsConfig::ClusterAutoscaler

  def initialize(@errors, @cluster_autoscaler)
  end

  def validate
    durations = {
      "scan_interval"                  => cluster_autoscaler.scan_interval,
      "scale_down_delay_after_add"     => cluster_autoscaler.scale_down_delay_after_add,
      "scale_down_delay_after_delete"  => cluster_autoscaler.scale_down_delay_after_delete,
      "scale_down_delay_after_failure" => cluster_autoscaler.scale_down_delay_after_failure,
      "max_node_provision_time"        => cluster_autoscaler.max_node_provision_time,
      "new_pod_scale_up_delay"         => cluster_autoscaler.new_pod_scale_up_delay,
    }

    durations.each { |field, value| validate_duration(field, value) }
  end

  private def validate_duration(field : String, value : String?)
    return if value.nil?
    return if value.matches?(DURATION)

    errors << "addons.cluster_autoscaler.#{field} must be a duration such as \"30s\", \"10m\" or \"1h30m\", not \"#{value}\"."
  end
end
