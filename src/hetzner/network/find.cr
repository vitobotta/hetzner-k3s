require "../client"
require "../network"
require "../networks_list"

class Hetzner::Network::Find
  getter hetzner_client : Hetzner::Client
  getter network_name : String

  def initialize(@hetzner_client, @network_name)
  end

  def run
    networks = NetworksList.from_json(hetzner_client.get("/networks")).networks

    networks.find do |network|
      network.name == network_name
    end
  end
end
