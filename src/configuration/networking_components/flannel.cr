class Configuration::NetworkingComponents::Flannel
  include YAML::Serializable
  include YAML::Serializable::Unmapped

  getter enabled : Bool = true
  getter encryption : Bool = true

  def initialize
  end

  def validate(errors, private_network)
    if enabled && !encryption && !private_network.enabled
      errors << "CNI encryption must be enabled when private networking is enabled"
    end
  end
end
