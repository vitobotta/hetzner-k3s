class Configuration::Models::NetworkingConfig::FirewallRule
  include YAML::Serializable
  include YAML::Serializable::Unmapped

  # Optional human-readable description for the rule (used in Hetzner firewall description field)
  getter description : String? = nil
  # Supported protocols: tcp, udp, icmp, esp, gre – defaults to tcp for backwards compatibility / convenience
  getter protocol : String = "tcp"
  # Direction of traffic: "in" or "out". Both directions are supported by Hetzner Cloud firewalls.
  getter direction : String = "in"
  # A single port ("80"), a range ("30000-32767"), or "any" for all ports (Hetzner API syntax)
  getter port : String = "any"
  # CIDR ranges allowed for incoming traffic when direction is "in"
  getter source_ips : Array(String) = [] of String
  # CIDR ranges allowed for outgoing traffic when direction is "out"
  getter destination_ips : Array(String) = [] of String

  def initialize
  end

  # Provides a default description if the user omits one.
  def effective_description : String
    desc = @description
    desc && !desc.empty? ? desc : "Allow #{protocol.upcase} #{port}"
  end
end
