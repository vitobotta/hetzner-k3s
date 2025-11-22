class Configuration::Models::EmbeddedRegistryMirror
  include YAML::Serializable
  include YAML::Serializable::Unmapped

  getter enabled : Bool = true
  getter private_registry_config : String? = nil

  def initialize
  end
end
