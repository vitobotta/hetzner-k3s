require "../../hetzner/client"
require "../../hetzner/network/find"

class Configuration::Settings::ExistingNetworkName
  getter hetzner_client : Hetzner::Client
  getter errors = [] of String
  getter existing_network_name : String?

  def initialize(@errors, @hetzner_client, @existing_network_name)
  end


  def validate
    network_name = existing_network_name

    return if network_name.nil?

    return if existing_network = Hetzner::Network::Find.new(@hetzner_client, network_name).run

    errors << "You have specified that you want to use the existing network named '#{network_name}' but this network doesn't exist"
  end
end
