require "./client"
require "./networks_list"

class Hetzner::Network
  include JSON::Serializable

  property id : Int32?
  property name : String?

  def self.create(hetzner_client, network_name, location)
    puts

    begin
      if network = find(hetzner_client, network_name)
        puts "Network already exists, skipping.\n"
      else
        puts "Creating network..."

        config = network_config(network_name, location)
        hetzner_client.not_nil!.post("/networks", config)
        network = find(hetzner_client, network_name)

        puts "...done.\n"
      end

      network
    rescue ex : Crest::RequestFailed
      STDERR.puts "Failed to create network: #{ex.message}"
      STDERR.puts ex.response

      exit 1
    end
  end

  private def self.find(hetzner_client, network_name)
    networks = NetworksList.from_json(hetzner_client.not_nil!.get("/networks")).networks

    networks.find do |network|
      network.name == network_name
    end
  end

  private def self.network_config(network_name, location)
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
