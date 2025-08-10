class Configuration::Models::NetworkingConfig::CNIConfig::Cilium
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
end
