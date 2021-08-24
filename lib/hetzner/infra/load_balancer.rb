module Hetzner
  class LoadBalancer
    def initialize(hetzner_client:, cluster_name:)
      @hetzner_client = hetzner_client
      @cluster_name = cluster_name
    end

    def create(location:, network_id:)
      @location = location
      @network_id = network_id

      puts

      if load_balancer = find_load_balancer
        puts "API load balancer already exists, skipping."
        puts
        return load_balancer["id"]
      end

      puts "Creating API load_balancer..."

      response = hetzner_client.post("/load_balancers", create_load_balancer_config).body
      puts "...API load balancer created."
      puts

      JSON.parse(response)["load_balancer"]["id"]
    end

    def delete(ha:)
      if load_balancer = find_load_balancer
        puts "Deleting API load balancer..." unless ha

        hetzner_client.post("/load_balancers/#{load_balancer["id"]}/actions/remove_target", remove_targets_config)

        hetzner_client.delete("/load_balancers", load_balancer["id"])
        puts "...API load balancer deleted." unless ha
      elsif ha
        puts "API load balancer no longer exists, skipping."
      end

      puts
    end

    private

      attr_reader :hetzner_client, :cluster_name, :load_balancer, :location, :network_id

      def load_balancer_name
        "#{cluster_name}-api"
      end

      def create_load_balancer_config
        {
          "algorithm": {
            "type": "round_robin"
          },
          "load_balancer_type": "lb11",
          "location": location,
          "name": load_balancer_name,
          "network": network_id,
          "public_interface": true,
          "services": [
            {
              "destination_port": 6443,
              "listen_port": 6443,
              "protocol": "tcp",
              "proxyprotocol": false
            }
          ],
          "targets": [
            {
              "label_selector": {
                "selector": "cluster=#{cluster_name},role=master"
              },
              "type": "label_selector",
              "use_private_ip": true
            }
          ]
        }
      end

      def remove_targets_config
        {
          "label_selector": {
            "selector": "cluster=#{cluster_name},role=master"
          },
          "type": "label_selector"
        }
      end

      def find_load_balancer
        hetzner_client.get("/load_balancers")["load_balancers"].detect{ |load_balancer| load_balancer["name"] == load_balancer_name }
      end

  end
end
