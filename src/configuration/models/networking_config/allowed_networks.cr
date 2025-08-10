class Configuration::Models::NetworkingConfig::AllowedNetworks
  include YAML::Serializable
  include YAML::Serializable::Unmapped

  getter ssh : Array(String) = ["0.0.0.0/0"]
  getter api : Array(String) = ["0.0.0.0/0"]

  def initialize
  end
end
