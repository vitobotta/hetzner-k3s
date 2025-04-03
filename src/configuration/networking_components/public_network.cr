class Configuration::NetworkingComponents::PublicNetwork
  include YAML::Serializable
  include YAML::Serializable::Unmapped

  getter ipv4 : Bool = true
  getter ipv6 : Bool = true
  getter ips_query_server_url : String?

  def initialize
  end

  def validate(errors, settings)
    return unless !settings.networking.private_network.enabled && ips_query_server_url.nil?

    errors << "ips_query_server_url must be set when private network is disabled"
  end
end
