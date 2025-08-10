require "../../models/networking_config/public_network"
require "../../main"

class Configuration::Validators::NetworkingConfig::PublicNetwork
  getter errors : Array(String)
  getter public_network : Configuration::Models::NetworkingConfig::PublicNetwork
  getter settings : Configuration::Main

  def initialize(@errors, @public_network, @settings)
  end

  def validate
    return unless !settings.networking.private_network.enabled && settings.networking.public_network.use_local_firewall && public_network.hetzner_ips_query_server_url.nil?

    errors << "hetzner_ips_query_server_url must be set when private network is disabled and the local firewall is used"
  end
end