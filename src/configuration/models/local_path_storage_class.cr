class Configuration::Models::LocalPathStorageClass
  include YAML::Serializable
  include YAML::Serializable::Unmapped

  getter enabled : Bool = false

  def initialize
  end
end
