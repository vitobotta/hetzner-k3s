class Configuration::NetworkingComponents::CNI
  include YAML::Serializable
  include YAML::Serializable::Unmapped

  getter enabled : Bool = true
  getter mode : String = "flannel"
  getter encryption : Bool = true

  def initialize
  end

  def validate(errors, private_network)
    return unless enabled

    if !encryption && !private_network.enabled
      errors << "CNI encryption must be enabled when private networking is enabled"
    end

    unless ["flannel", "cilium"].includes?(mode)
      errors << "CNI mode must be either 'flannel' or 'cilium' when CNI is enabled"
    end
  end
end
