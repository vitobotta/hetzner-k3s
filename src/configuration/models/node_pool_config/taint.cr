require "yaml"

class Configuration::Taint
  include YAML::Serializable

  property key : String?
  property value : String?
end
