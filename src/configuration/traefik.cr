class Configuration::Traefik
  include YAML::Serializable
  include YAML::Serializable::Unmapped

  # Whether to install the built-in Traefik ingress controller (default: disabled)
  getter enabled : Bool = false

  def initialize
  end

  def enabled?
    enabled
  end
end 