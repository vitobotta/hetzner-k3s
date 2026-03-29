require "../../models/networking_config/ssh"
require "../../models/networking_config/public_network"

class Configuration::Validators::NetworkingConfig::Tailscale
  getter errors : Array(String)
  getter ssh : Configuration::Models::NetworkingConfig::SSH
  getter public_network : Configuration::Models::NetworkingConfig::PublicNetwork

  def initialize(@errors, @ssh, @public_network)
  end

  def validate
    return unless ssh.use_tailscale

    validate_hostname_suffix
    validate_auth_key
    validate_public_network_not_disabled
  end

  private def validate_hostname_suffix
    if ssh.tailscale_hostname_suffix.empty?
      errors << "tailscale_hostname_suffix is required when use_tailscale is true (e.g. \"my-tailnet.ts.net\")"
    end
  end

  private def validate_auth_key
    if ssh.tailscale_auth_key.empty?
      errors << "A Tailscale auth key is required when use_tailscale is true. Set tailscale_auth_key in the configuration or the TAILSCALE_AUTH_KEY environment variable."
    end
  end

  private def validate_public_network_not_disabled
    if !public_network.ipv4 && !public_network.ipv6
      errors << "When use_tailscale is true and ipv4 is disabled, ipv6 must be enabled so nodes can reach the Tailscale coordination server."
    end
  end
end
