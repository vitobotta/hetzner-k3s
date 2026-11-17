require "yaml"

# k3s installs local-path as a default StorageClass. `default: false` keeps the class but strips the
# is-default-class annotation, so another class can stay the cluster default.
class Configuration::Models::AddonsConfig::LocalPathStorageClass
  include YAML::Serializable
  include YAML::Serializable::Unmapped

  getter enabled : Bool = false
  getter default : Bool = true

  def initialize(@enabled : Bool = false, @default : Bool = true)
  end

  def enabled? : Bool
    enabled
  end

  def default? : Bool
    default
  end
end
