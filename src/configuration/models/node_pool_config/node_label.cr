require "yaml"

class Configuration::NodeLabel
  include YAML::Serializable

  property key : String?
  property value : String?
end
