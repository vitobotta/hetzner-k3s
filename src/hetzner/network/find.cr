require "../client"
require "../network"
require "../networks_list"

class Hetzner::Network::Find
  getter hetzner_client : Hetzner::Client
  getter network_name : String

  def initialize(@hetzner_client, @network_name)
  end

  def run
    fetch_networks.find { |network| network.name == network_name }
  end

  private def fetch_networks
    Retriable.retry(max_attempts: 10, backoff: false, base_interval: 5.seconds) do
      success, response = hetzner_client.get("/networks")

      if success
        NetworksList.from_json(response).networks
      else
        STDERR.puts "[#{default_log_prefix}] Failed to fetch networks: #{response}"
        STDERR.puts "[#{default_log_prefix}] Retrying to fetch networks in 5 seconds..."
        raise "Failed to fetch networks"
      end
    end
  end

  private def default_log_prefix
    "Private network"
  end
end
