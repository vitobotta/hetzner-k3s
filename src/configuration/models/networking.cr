require "./networking_config/cni"
require "./networking_config/allowed_networks"
require "./networking_config/private_network"
require "./networking_config/public_network"
require "./networking_config/ssh"
require "../../hetzner/client"
require "../../hetzner/network/find"

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
      getter cluster_cidr : String = "10.244.0.0/16"
      getter service_cidr : String = "10.43.0.0/16"
      getter cluster_dns : String = "10.43.0.10"

      def initialize
      end

      def validate(errors, settings, hetzner_client, private_network)
        Configuration::Validators::Networking::CNI.new(errors, cni, private_network).validate
        Configuration::Validators::Networking::AllowedNetworks.new(errors, allowed_networks).validate
        Configuration::Validators::Networking::PrivateNetwork.new(errors, private_network, hetzner_client).validate
        Configuration::Validators::Networking::PublicNetwork.new(errors, public_network, settings).validate
        Configuration::Validators::Networking::SSH.new(errors, ssh, hetzner_client, settings.cluster_name).validate
      end
    end
  end
end
