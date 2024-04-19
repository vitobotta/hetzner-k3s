class Configuration::NetworkingComponents::CNI
  include YAML::Serializable
  include YAML::Serializable::Unmapped

  getter enabled : Bool = true
  getter mode : String = "flannel"
  getter encryption : Bool = true

  def initialize
  end

  def mode
    enabled ? @mode : "none"
  end

  def validate(errors, private_network)
    if enabled && !["flannel", "cilium"].includes?(mode)
      errors << "CNI must be 'flannel' or 'cilium' when enabled"
    end

    if enabled && !encryption && !private_network.enabled
      errors << "CNI encryption must be enabled when private networking is enabled"
    end
  end
end
