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
    validate_version
  end

  # A MagicDNS domain, e.g. "tail1234ab.ts.net". Rejects a pasted admin URL,
  # a trailing slash or a trailing dot, all of which otherwise only surface
  # after the SSH retry budget has been spent on every node.
  MAGICDNS_DOMAIN = /\A[a-z0-9]([a-z0-9-]*[a-z0-9])?(\.[a-z0-9]([a-z0-9-]*[a-z0-9])?)+\z/

  private def validate_hostname_suffix
    suffix = tailscale.hostname_suffix

    if suffix.empty?
      errors << "tailscale.hostname_suffix is required when tailscale is enabled (e.g. \"my-tailnet.ts.net\", found in the Tailscale admin console under DNS)"
    elsif !MAGICDNS_DOMAIN.matches?(suffix)
      errors << "tailscale.hostname_suffix must be a MagicDNS domain such as \"my-tailnet.ts.net\" (lowercase, no scheme, no trailing slash or dot)"
    end
  end

  private def validate_auth_key
    key = tailscale.auth_key

    if key.empty?
      errors << "A Tailscale auth key is required when tailscale is enabled. Set tailscale.auth_key in the configuration or the TAILSCALE_AUTH_KEY environment variable."
    elsif !key.starts_with?("tskey-")
      errors << "tailscale.auth_key does not look like a Tailscale auth key (it should start with \"tskey-\")"
    end
  end

  private def validate_version
    version = tailscale.version
    return if version.empty?

    unless /\A\d+\.\d+\.\d+\z/.matches?(version)
      errors << "tailscale.version must be a plain version such as \"1.80.2\", or empty to install the repository's current stable package"
    end
  end
end
