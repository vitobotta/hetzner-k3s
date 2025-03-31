class Configuration::NetworkingComponents::Tailscale
  include YAML::Serializable
  include YAML::Serializable::Unmapped

  getter server_url : String = "https://controlplane.tailscale.com"
  getter auth_key : String = ENV.fetch("TAILSCALE_AUTH_KEY", "")

  def initialize
  end

  def validate(errors)
    if server_url.blank?
      errors << "Tailscale server URL must be specified"
    end

    if auth_key.blank?
      errors << "Tailscale auth key must be specified"
    end
  end
end
