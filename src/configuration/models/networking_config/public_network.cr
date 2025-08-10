class Configuration::Models::NetworkingConfig::PublicNetwork
  include YAML::Serializable
  include YAML::Serializable::Unmapped

  getter ipv4 : Bool = true
  getter ipv6 : Bool = true
  getter hetzner_ips_query_server_url : String?
  getter use_local_firewall : Bool = false

  def initialize
  end
end
