class Configuration::CSIDriver
  include YAML::Serializable
  include YAML::Serializable::Unmapped

  # Whether to install the Hetzner CSI driver (default: true)
  getter enabled : Bool = true

  def initialize
  end

  def enabled?
    enabled
  end
end 