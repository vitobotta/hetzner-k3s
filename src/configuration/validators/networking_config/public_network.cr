require "../../models/networking_config/public_network"
require "../../main"

class Configuration::Validators::NetworkingConfig::PublicNetwork
  getter errors : Array(String)
  getter public_network : Configuration::Models::NetworkingConfig::PublicNetwork
  getter settings : Configuration::Main

  def initialize(@errors, @public_network, @settings)
  end

  def validate
    validate_hetzner_ips_query_server_url
    validate_address_families
    validate_ips_token
  end

  private def validate_ips_token
    token = public_network.hetzner_ips_token
    return if token.nil?
    return unless token.strip.empty?

    errors << "networking.public_network.hetzner_ips_token is set but empty. Remove the key to fall back to hetzner_token."
  end

  private def validate_hetzner_ips_query_server_url
    return unless !settings.networking.private_network.enabled && settings.networking.public_network.use_local_firewall && public_network.hetzner_ips_query_server_url.nil?

    errors << "hetzner_ips_query_server_url must be set when private network is disabled and the local firewall is used"
  end

  # Without a public address only the private one is left, so it has to be the one to connect to.
  private def validate_address_families
    return if public_network.ipv4 || public_network.ipv6

    unless settings.networking.private_network.enabled && settings.networking.ssh.use_private_ip
      errors << "networking.public_network.ipv4 and networking.public_network.ipv6 are both false: enable a private network and set networking.ssh.use_private_ip to true"
    end
  end
end
