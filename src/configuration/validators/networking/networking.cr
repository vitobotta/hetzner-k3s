require "../../../hetzner/client"
require "../../models/networking"
require "../../models/networking_config/cni"
require "../../models/networking_config/allowed_networks"
require "../../models/networking_config/private_network"
require "../../models/networking_config/public_network"
require "../../models/networking_config/ssh"
require "./cni"
require "./allowed_networks"
require "./private_network"
require "./public_network"
require "./ssh"

class Configuration::Validators::NetworkingValidator
  getter errors : Array(String)
  getter networking : Configuration::Models::Networking
  getter settings : Configuration::Main
  getter hetzner_client : Hetzner::Client
  getter private_network : Configuration::Models::NetworkingConfig::PrivateNetwork

  def initialize(@errors, @networking, @settings, @hetzner_client, @private_network)
  end

  def validate
    Configuration::Validators::Networking::CNI.new(errors, networking.cni, private_network).validate
    Configuration::Validators::Networking::AllowedNetworks.new(errors, networking.allowed_networks).validate
    Configuration::Validators::Networking::PrivateNetwork.new(errors, private_network, hetzner_client).validate
    Configuration::Validators::Networking::PublicNetwork.new(errors, networking.public_network, settings).validate
    Configuration::Validators::Networking::SSH.new(errors, networking.ssh, hetzner_client, settings.cluster_name).validate
  end
end