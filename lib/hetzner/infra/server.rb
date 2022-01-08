module Hetzner
  class Server
    def initialize(hetzner_client:, cluster_name:)
      @hetzner_client = hetzner_client
      @cluster_name = cluster_name
    end

    def create(location:, instance_type:, instance_id:, firewall_id:, network_id:, ssh_key_id:, placement_group_id:, image:, additional_packages: [])
      @additional_packages = additional_packages

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
        image: image,
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
        },
        placement_group: placement_group_id
      }

      response = hetzner_client.post("/servers", server_config)
      response_body = response.body

      server = JSON.parse(response_body)["server"]

      unless server
        puts "Error creating server #{server_name}. Response details below:"
        puts
        p response
        return
      end

      puts "...server #{server_name} created."
      puts

      server
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

      attr_reader :hetzner_client, :cluster_name, :additional_packages

      def find_server(server_name)
        hetzner_client.get("/servers")["servers"].detect{ |network| network["name"] == server_name }
      end

      def user_data
        packages = ["fail2ban"]
        packages += additional_packages if additional_packages
        packages = "'" + packages.join("', '") + "'"

        <<~EOS
          #cloud-config
          packages: [#{packages}]
          runcmd:
            - sed -i 's/[#]*PermitRootLogin yes/PermitRootLogin prohibit-password/g' /etc/ssh/sshd_config
            - sed -i 's/[#]*PasswordAuthentication yes/PasswordAuthentication no/g' /etc/ssh/sshd_config
            - systemctl restart sshd
            - systemctl stop systemd-resolved
            - systemctl disable systemd-resolved
            - rm /etc/resolv.conf
            - echo "nameserver 1.1.1.1" > /etc/resolv.conf
            - echo "nameserver 1.0.0.1" >> /etc/resolv.conf
        EOS
      end

  end
end
