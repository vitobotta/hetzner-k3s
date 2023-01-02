require "yaml"

class Configuration::Autoscaling
  include YAML::Serializable

  property enabled : Bool = false
  property min_instances : Int32 = 0
  property max_instances : Int32 = 0
end
