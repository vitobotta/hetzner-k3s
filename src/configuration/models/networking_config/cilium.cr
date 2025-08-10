class Configuration::NetworkingConfig::Cilium
  include YAML::Serializable
  include YAML::Serializable::Unmapped

  getter chart_version : String = "v1.17.2"
  getter helm_values_path : String?
  getter encryption_type : String? = nil
  getter routing_mode : String? = nil
  getter tunnel_protocol : String? = nil
  getter hubble_enabled : Bool? = nil
  getter hubble_metrics : String? = nil
  getter hubble_relay_enabled : Bool? = nil
  getter hubble_ui_enabled : Bool? = nil
  getter k8s_service_host : String? = nil
  getter k8s_service_port : Int32? = nil
  getter operator_replicas : Int32? = nil
  getter operator_memory_request : String? = nil
  getter agent_memory_request : String? = nil

  def initialize
  end

  def validate(errors)
    if helm_values_path
      path = helm_values_path.not_nil!
      if !File.exists?(path)
        errors << "Cilium helm_values_path '#{path}' does not exist"
      elsif !File.file?(path)
        errors << "Cilium helm_values_path '#{path}' is not a file"
      end
    end

    if chart_version.nil? || chart_version.empty?
      errors << "Cilium chart_version is required"
    end
  end
end
