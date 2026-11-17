class Configuration::Models::NetworkingConfig::CNIConfig::CiliumConnectivityCheck
  include YAML::Serializable
  include YAML::Serializable::Unmapped

  DEFAULT_IMAGE           = "nicolaka/netshoot:v0.16"
  DEFAULT_TIMEOUT_SECONDS = 300

  getter enabled : Bool = true
  getter image : String = DEFAULT_IMAGE
  getter timeout_seconds : Int32 = DEFAULT_TIMEOUT_SECONDS

  def initialize
  end

  def enabled?
    enabled
  end
end
