require "ipaddress"

require "../../../hetzner/network/find"
require "../../../hetzner/client"
require "../../models/networking_config/private_network"

class Configuration::Validators::Networking::PrivateNetwork
  getter errors : Array(String)
  getter private_network : Configuration::Models::NetworkingConfig::PrivateNetwork
  getter hetzner_client : Hetzner::Client

  def initialize(@errors, @private_network, @hetzner_client)
  end

  def validate
    validate_existing_network_name(errors, hetzner_client)
    validate_subnet(errors)
  end

  private def validate_subnet(errors)
    IPAddress.new(private_network.subnet).network?
  rescue ArgumentError
    errors << "private network subnet #{private_network.subnet} is not a valid network in CIDR notation"
  end

  private def validate_existing_network_name(errors, hetzner_client)
    return if private_network.existing_network_name.empty?
    return if Hetzner::Network::Find.new(hetzner_client, private_network.existing_network_name).run

    errors << "You have specified that you want to use the existing network named '#{private_network.existing_network_name}' but this network doesn't exist"
  end
end