require "../client"
require "./find"

class Hetzner::Network::Create
  getter hetzner_client : Hetzner::Client
  getter network_name : String
  getter location : String
  getter network_finder : Hetzner::Network::Find
  getter locations : Array(Hetzner::Location)
  getter private_network : String
  getter private_network_subnet : String

  def initialize(@hetzner_client, @network_name, @location, @locations, @private_network, @private_network_subnet)
    @network_finder = Hetzner::Network::Find.new(@hetzner_client, @network_name)
  end

  def run
    network = network_finder.run

    if network
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
    network_zone = locations.find { |l| l.name == location }.not_nil!.network_zone

    {
      name: network_name,
      ip_range: private_network,
      subnets: [
        {
          ip_range: private_network_subnet,
          network_zone: network_zone,
          type: "cloud"
        }
      ]
    }
  end
end
