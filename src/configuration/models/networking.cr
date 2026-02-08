require "./networking_config/cni"
require "./networking_config/allowed_networks"
require "./networking_config/private_network"
require "./networking_config/public_network"
require "./networking_config/ssh"

module Configuration
  module Models
    class Networking
      include YAML::Serializable
      include YAML::Serializable::Unmapped

      getter cni : ::Configuration::Models::NetworkingConfig::CNI = ::Configuration::Models::NetworkingConfig::CNI.new
      getter private_network : ::Configuration::Models::NetworkingConfig::PrivateNetwork = ::Configuration::Models::NetworkingConfig::PrivateNetwork.new
      getter public_network : ::Configuration::Models::NetworkingConfig::PublicNetwork = ::Configuration::Models::NetworkingConfig::PublicNetwork.new
      getter allowed_networks : ::Configuration::Models::NetworkingConfig::AllowedNetworks = ::Configuration::Models::NetworkingConfig::AllowedNetworks.new
      getter ssh : ::Configuration::Models::NetworkingConfig::SSH = ::Configuration::Models::NetworkingConfig::SSH.new
      getter node_port_firewall_enabled : Bool = true
      getter node_port_range : String = "30000-32767"
      getter cluster_cidr : String = "10.244.0.0/16"
      getter service_cidr : String = "10.43.0.0/16"
      getter cluster_dns : String = "10.43.0.10"

      def node_port_range_iptables : String
        node_port_range.includes?("-") ? node_port_range.gsub("-", ":") : node_port_range
      end

      def initialize
      end
    end
  end
end
