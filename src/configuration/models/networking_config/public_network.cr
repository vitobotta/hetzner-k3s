class Configuration::Models::NetworkingConfig::PublicNetwork
  include YAML::Serializable
  include YAML::Serializable::Unmapped

  getter ipv4 : Bool = true
  getter ipv6 : Bool = true
  getter hetzner_ips_query_server_url : String?
  # Optional read-only Hetzner token for the local firewall's node IP lookup, so the read-write token
  # does not have to sit on every node. Falls back to the main token when unset.
  getter hetzner_ips_token : String?
  # Filtering inside the VMs, instead of Hetzner's own cloud firewall.
  getter use_local_firewall : Bool = false
  # Hetzner's cloud firewall, attached by label selector. Separate from use_local_firewall: with both
  # off the nodes have no filtering at all.
  getter use_hetzner_firewall : Bool = true

  def initialize
  end
end
