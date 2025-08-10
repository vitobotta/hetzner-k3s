require "./networking_config/cni"
require "./networking_config/allowed_networks"
require "./networking_config/private_network"
require "./networking_config/public_network"
require "./networking_config/ssh"
require "../../hetzner/client"
require "../../hetzner/network/find"

module Configuration
  class Networking
    include YAML::Serializable
    include YAML::Serializable::Unmapped

    getter cni : ::Configuration::NetworkingConfig::CNI = ::Configuration::NetworkingConfig::CNI.new
    getter private_network : ::Configuration::NetworkingConfig::PrivateNetwork = ::Configuration::NetworkingConfig::PrivateNetwork.new
    getter public_network : ::Configuration::NetworkingConfig::PublicNetwork = ::Configuration::NetworkingConfig::PublicNetwork.new
    getter allowed_networks : ::Configuration::NetworkingConfig::AllowedNetworks = ::Configuration::NetworkingConfig::AllowedNetworks.new
    getter ssh : ::Configuration::NetworkingConfig::SSH = ::Configuration::NetworkingConfig::SSH.new
    getter cluster_cidr : String = "10.244.0.0/16"
    getter service_cidr : String = "10.43.0.0/16"
    getter cluster_dns : String = "10.43.0.10"

    def initialize
    end

    def validate(errors, settings, hetzner_client, private_network)
      cni.validate(errors, private_network)
      allowed_networks.validate(errors)
      private_network.validate(errors, hetzner_client)
      public_network.validate(errors, settings)
      ssh.validate(errors, hetzner_client, settings.cluster_name)
    end
  end
end
