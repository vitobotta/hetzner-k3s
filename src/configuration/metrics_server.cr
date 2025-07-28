class Configuration::MetricsServer
  include YAML::Serializable
  include YAML::Serializable::Unmapped

  # Whether to install the built-in metrics-server addon (default: disabled)
  getter enabled : Bool = false

  def initialize
  end

  def enabled?
    enabled
  end
end 