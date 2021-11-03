module Hetzner
  class Network
    def initialize(hetzner_client:, cluster_name:)
      @hetzner_client = hetzner_client
      @cluster_name = cluster_name
    end

    def create(location:)
      @location = location
      puts

      if network = find_network
        puts "Private network already exists, skipping."
        puts
        return network["id"]
      end

      puts "Creating private network..."

      response = hetzner_client.post("/networks", network_config).body

      puts "...private network created."
      puts

      JSON.parse(response)["network"]["id"]
    end

    def delete
      if network = find_network
        puts "Deleting network..."
        hetzner_client.delete("/networks", network["id"])
        puts "...network deleted."
      else
        puts "Network no longer exists, skipping."
      end

      puts
    end

    private

      attr_reader :hetzner_client, :cluster_name, :location

      def network_config
        {
          name: cluster_name,
          ip_range: "10.0.0.0/16",
          subnets: [
            {
              ip_range: "10.0.0.0/16",
              network_zone: (location ? "us-east" : "eu-central"),
              type: "cloud"
            }
          ]
        }
      end

      def find_network
        hetzner_client.get("/networks")["networks"].detect{ |network| network["name"] == cluster_name }
      end

  end
end
