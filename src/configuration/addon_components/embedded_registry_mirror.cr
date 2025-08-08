class Configuration::AddonComponents::EmbeddedRegistryMirror
  include YAML::Serializable
  include YAML::Serializable::Unmapped

  getter enabled : Bool = true

  def initialize
  end
end
