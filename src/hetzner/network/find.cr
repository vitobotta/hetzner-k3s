require "../client"
require "../network"
require "../networks_list"

class Hetzner::Network::Find
  getter hetzner_client : Hetzner::Client
  getter network_name : String

  def initialize(@hetzner_client, @network_name)
  end

  def run
    networks = fetch_networks

    networks.find { |network| network.name == network_name }
  end

  private def fetch_networks
    NetworksList.from_json(hetzner_client.get("/networks")).networks
  rescue ex : Crest::RequestFailed
    STDERR.puts "Failed to fetch networks: #{ex.message}"
    STDERR.puts ex.response
    exit 1
  end
end
