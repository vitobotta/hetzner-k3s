module Hetzner
  class Server
    def initialize(hetzner_client:, cluster_name:)
      @hetzner_client = hetzner_client
      @cluster_name = cluster_name
    end

    def create(location:, instance_type:, instance_id:, firewall_id:, network_id:, ssh_key_id:)
      puts

      server_name = "#{cluster_name}-#{instance_type}-#{instance_id}"

      if server = find_server(server_name)
        puts "Server #{server_name} already exists, skipping."
        puts
        return server
      end

      puts "Creating server #{server_name}..."

      server_config = {
        name: server_name,
        location: location,
        image: "ubuntu-20.04",
        firewalls: [
          { firewall: firewall_id }
        ],
        networks: [
          network_id
        ],
        server_type: instance_type,
        ssh_keys: [
          ssh_key_id
        ],
        user_data: user_data,
        labels: {
          cluster: cluster_name,
          role: (server_name =~ /master/ ? "master" : "worker")
        }
      }

      response = hetzner_client.post("/servers", server_config).body

      puts "...server #{server_name} created."
      puts

      JSON.parse(response)["server"]
    end

    def delete(server_name:)
      if server = find_server(server_name)
        puts "Deleting server #{server_name}..."
        hetzner_client.delete "/servers", server["id"]
        puts "...server #{server_name} deleted."
      else
        puts "Server #{server_name} no longer exists, skipping."
      end
    end

    private

      attr_reader :hetzner_client, :cluster_name

      def find_server(server_name)
        hetzner_client.get("/servers")["servers"].detect{ |network| network["name"] == server_name }
      end

      def user_data
        <<~EOS
          #cloud-config
          packages:
            - fail2ban
          runcmd:
            - sed -i 's/[#]*PermitRootLogin yes/PermitRootLogin prohibit-password/g' /etc/ssh/sshd_config
            - sed -i 's/[#]*PasswordAuthentication yes/PasswordAuthentication no/g' /etc/ssh/sshd_config
            - systemctl restart sshd
        EOS
      end

  end
end
