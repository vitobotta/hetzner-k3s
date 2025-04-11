class Configuration::NetworkingComponents::Cilium
  include YAML::Serializable
  include YAML::Serializable::Unmapped

  getter chart_version : String = "v1.17.2"

  def initialize
  end
end
