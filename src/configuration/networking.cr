require "./networking_components/cni"
require "./networking_components/allowed_networks"
require "./networking_components/private_network"
require "./networking_components/public_network"
require "./networking_components/ssh"
require "../hetzner/client"
require "../hetzner/network/find"

module Configuration
  class Networking
    include YAML::Serializable
    include YAML::Serializable::Unmapped

    getter cni : ::Configuration::NetworkingComponents::CNI = ::Configuration::NetworkingComponents::CNI.new
    getter private_network : ::Configuration::NetworkingComponents::PrivateNetwork = ::Configuration::NetworkingComponents::PrivateNetwork.new
    getter public_network : ::Configuration::NetworkingComponents::PublicNetwork = ::Configuration::NetworkingComponents::PublicNetwork.new
    getter allowed_networks : ::Configuration::NetworkingComponents::AllowedNetworks = ::Configuration::NetworkingComponents::AllowedNetworks.new
    getter ssh : ::Configuration::NetworkingComponents::SSH = ::Configuration::NetworkingComponents::SSH.new
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
    end
  end
end
