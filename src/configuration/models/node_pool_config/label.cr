require "yaml"

class Configuration::Label
  include YAML::Serializable

  property key : String?
  property value : String?
end
