require "yaml"

class Configuration::NodeTaint
  include YAML::Serializable

  property key : String?
  property value : String?
end
