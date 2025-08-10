require "yaml"

class Configuration::Models::NodePoolConfig::Label
  include YAML::Serializable

  property key : String?
  property value : String?
end
