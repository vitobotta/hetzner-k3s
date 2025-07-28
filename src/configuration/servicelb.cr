class Configuration::ServiceLB
  include YAML::Serializable
  include YAML::Serializable::Unmapped

  # Whether to install the built-in ServiceLB load balancer (default: disabled)
  getter enabled : Bool = false

  def initialize
  end

  def enabled?
    enabled
  end
end 