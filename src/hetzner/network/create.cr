require "../client"
require "../networks"
require "../networks_list"

class Hetzner::Network::Create
  def initialize(@hetzner_client, @network_name, @location)
  end

  def run
    puts

    begin
      if network = find_network
        puts "Network already exists, skipping.\n".colorize(:green)
      else
        puts "Creating network...".colorize(:green)

        hetzner_client.post("/networks", network_config)
        network = find_network

        puts "...network created.\n".colorize(:green)
      end

      network.not_nil!

    rescue ex : Crest::RequestFailed
      STDERR.puts "Failed to create network: #{ex.message}".colorize(:red)
      STDERR.puts ex.response

      exit 1
    end
  end

  private def find_network
    networks = NetworksList.from_json(hetzner_client.get("/networks")).networks

    networks.find do |network|
      network.name == network_name
    end
  end

  private def network_config
    {
      name: network_name,
      ip_range: "10.0.0.0/16",
      subnets: [
        {
          ip_range: "10.0.0.0/16",
          network_zone: (location == "ash" ? "us-east" : "eu-central"),
          type: "cloud"
        }
      ]
    }
  end
end
