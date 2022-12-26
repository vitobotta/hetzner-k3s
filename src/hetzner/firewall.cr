require "./client"
require "./firewalls_list"

class Hetzner::Firewall
  include JSON::Serializable

  property id : Int32?
  property name : String?

  def self.create(hetzner_client, firewall_name, ssh_allowed_networks, api_allowed_networks, high_availability)
    puts

    config = firewall_config(firewall_name, ssh_allowed_networks, api_allowed_networks, high_availability)

    begin
      if firewall = find(hetzner_client, firewall_name)
        puts "Updating firewall...\n"

        hetzner_client.not_nil!.post("/firewalls/#{firewall.id}/actions/set_rules", config)
      else
        puts "Creating firewall..."

        hetzner_client.not_nil!.post("/firewalls", config)
      end

      puts "...done.\n"

      find(hetzner_client, firewall_name)

    rescue ex : Crest::RequestFailed
      STDERR.puts "Failed to create firewall: #{ex.message}"
      STDERR.puts ex.response

      exit 1
    end
  end

  private def self.find(hetzner_client, firewall_name)
    firewalls = FirewallsList.from_json(hetzner_client.not_nil!.get("/firewalls")).firewalls

    firewalls.find do |firewall|
      firewall.name == firewall_name
    end
  end

  private def self.firewall_config(firewall_name, ssh_allowed_networks, api_allowed_networks, high_availability)
    rules = [
      {
        description: "Allow port 22 (SSH)",
        direction: "in",
        protocol: "tcp",
        port: "22",
        source_ips: ssh_allowed_networks,
        destination_ips: [] of String
      },
      {
        description: "Allow ICMP (ping)",
        direction: "in",
        protocol: "icmp",
        source_ips: [
          "0.0.0.0/0",
          "::/0"
        ],
        destination_ips: [] of String
      },
      {
        description: "Allow all TCP traffic between nodes on the private network",
        direction: "in",
        protocol: "tcp",
        port: "any",
        source_ips: [
          "10.0.0.0/16"
        ],
        destination_ips: [] of String
      },
      {
        description: "Allow all UDP traffic between nodes on the private network",
        direction: "in",
        protocol: "udp",
        port: "any",
        source_ips: [
          "10.0.0.0/16"
        ],
        destination_ips: [] of String
      }
    ]

    unless high_availability
      rules << {
        description: "Allow port 6443 (Kubernetes API server)",
        direction: "in",
        protocol: "tcp",
        port: "6443",
        source_ips: api_allowed_networks,
        destination_ips: [] of String
      }
    end

    {
      name: firewall_name,
      rules: rules
    }
  end
end
