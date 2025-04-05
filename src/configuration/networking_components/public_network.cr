class Configuration::NetworkingComponents::PublicNetwork
  include YAML::Serializable
  include YAML::Serializable::Unmapped

  getter ipv4 : Bool = true
  getter ipv6 : Bool = true
  getter hetzner_ips_query_server_url : String?
  getter use_local_firewall : Bool = false

  def initialize
  end

  def validate(errors, settings)
    return unless !settings.networking.private_network.enabled && settings.networking.public_network.use_local_firewall && hetzner_ips_query_server_url.nil?

    errors << "hetzner_ips_query_server_url must be set when private network is disabled and the local firewall is used"
  end
end
