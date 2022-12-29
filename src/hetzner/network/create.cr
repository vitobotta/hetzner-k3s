require "../client"
require "./find"

class Hetzner::Network::Create
  getter hetzner_client : Hetzner::Client
  getter network_name : String
  getter location : String
  getter network_finder : Hetzner::Network::Find

  def initialize(@hetzner_client, @network_name, @location)
    @network_finder = Hetzner::Network::Find.new(@hetzner_client, @network_name)
  end

  def run
    if network = network_finder.run
      puts "Network already exists, skipping."
    else
      print "Creating network..."

      hetzner_client.post("/networks", network_config)
      network = network_finder.run

      puts "done."
    end

    network.not_nil!

  rescue ex : Crest::RequestFailed
    STDERR.puts "Failed to create network: #{ex.message}"
    STDERR.puts ex.response

    exit 1
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
