require "yaml"

class Configuration::Models::NodePoolConfig::Taint
  include YAML::Serializable

  property key : String?
  property value : String?
end
