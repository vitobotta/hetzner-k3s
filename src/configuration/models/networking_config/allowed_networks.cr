require "./firewall_rule"

class Configuration::Models::NetworkingConfig::AllowedNetworks
  include YAML::Serializable
  include YAML::Serializable::Unmapped

  getter ssh : Array(String) = ["0.0.0.0/0"]
  getter api : Array(String) = ["0.0.0.0/0"]
  getter custom_firewall_rules : Array(Configuration::Models::NetworkingConfig::FirewallRule) = [] of Configuration::Models::NetworkingConfig::FirewallRule

  def initialize
  end
end
