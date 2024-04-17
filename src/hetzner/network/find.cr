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
    STDERR.puts "[#{default_log_prefix}] Failed to fetch networks: #{ex.message}"
    exit 1
  end

  private def default_log_prefix
    "Private network"
  end
end
