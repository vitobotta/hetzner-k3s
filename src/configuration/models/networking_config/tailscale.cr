class Configuration::Models::NetworkingConfig::Tailscale
  include YAML::Serializable
  include YAML::Serializable::Unmapped

  getter enabled : Bool = false
  getter hostname_suffix : String = ""
  getter auth_key : String = ENV.fetch("TAILSCALE_AUTH_KEY", "")

  def initialize
  end

  # Suffix used to route SSH connections through the tailnet.
  # Returns an empty string when Tailscale is disabled, so SSH falls back to IPs.
  def ssh_hostname_suffix : String
    enabled ? hostname_suffix : ""
  end
end
