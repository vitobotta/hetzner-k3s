class Configuration::Models::NetworkingConfig::PrivateNetwork
  include YAML::Serializable
  include YAML::Serializable::Unmapped

  getter enabled : Bool = true
  getter subnet : String = "10.0.0.0/16"
  getter existing_network_name : String = ""

  def initialize
  end
end
