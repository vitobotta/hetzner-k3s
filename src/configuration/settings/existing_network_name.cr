require "../../hetzner/client"
require "../../hetzner/network/find"

class Configuration::Settings::ExistingNetworkName
  getter hetzner_client : Hetzner::Client
  getter errors : Array(String)
  getter existing_network_name : String?

  def initialize(@errors, @hetzner_client, @existing_network_name)
  end

  def validate
    return if existing_network_name.nil?

    return if Hetzner::Network::Find.new(@hetzner_client, existing_network_name.not_nil!).run

    errors << "You have specified that you want to use the existing network named '#{existing_network_name}' but this network doesn't exist"
  end
end
