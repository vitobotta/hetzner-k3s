require "../../models/networking_config/tailscale"

class Configuration::Validators::NetworkingConfig::Tailscale
  getter errors : Array(String)
  getter tailscale : Configuration::Models::NetworkingConfig::Tailscale

  def initialize(@errors, @tailscale)
  end

  def validate
    return unless tailscale.enabled

    validate_hostname_suffix
    validate_auth_key
  end

  private def validate_hostname_suffix
    if tailscale.hostname_suffix.empty?
      errors << "tailscale.hostname_suffix is required when tailscale is enabled (e.g. \"my-tailnet.ts.net\", found in the Tailscale admin console under DNS)"
    end
  end

  private def validate_auth_key
    if tailscale.auth_key.empty?
      errors << "A Tailscale auth key is required when tailscale is enabled. Set tailscale.auth_key in the configuration or the TAILSCALE_AUTH_KEY environment variable."
    end
  end
end
