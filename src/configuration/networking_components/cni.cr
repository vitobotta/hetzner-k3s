class Configuration::NetworkingComponents::CNI
  include YAML::Serializable
  include YAML::Serializable::Unmapped

  getter enabled : Bool = true
  getter mode : String = "flannel"
  getter encryption : Bool = true

  def initialize
  end

  def validate(errors)
    return unless enabled && ["flannel"].includes?(mode)

    errors << "CNI must be 'flannel'"
  end
end
