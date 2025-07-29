class Configuration::NetworkingComponents::Cilium
  include YAML::Serializable
  include YAML::Serializable::Unmapped

  getter chart_version : String = "v1.17.2"
  getter helm_values_path : String?

  def initialize
  end
end
