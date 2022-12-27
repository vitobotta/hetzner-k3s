require "../client"
require "../firewall"
require "../firewalls_list"

class Hetzner::Firewall::Create
  getter hetzner_client : Hetzner::Client
  getter firewall_name : String
  getter ssh_allowed_networks : Array(String)
  getter api_allowed_networks : Array(String)
  getter high_availability : Bool

  def initialize(
      @hetzner_client,
      @firewall_name,
      @ssh_allowed_networks,
      @api_allowed_networks,
      @high_availability
    )
  end

  def run
    puts

    begin
      if firewall = find_firewall
        puts "Updating firewall...".colorize(:magenta)

        hetzner_client.post("/firewalls/#{firewall.id}/actions/set_rules", firewall_config)

        puts "...firewall updated.\n".colorize(:magenta)
      else
        puts "Creating firewall...".colorize(:magenta)

        hetzner_client.post("/firewalls", firewall_config)
        firewall = find_firewall

        puts "...firewall created.\n".colorize(:magenta)
      end

      firewall.not_nil!

    rescue ex : Crest::RequestFailed
      STDERR.puts "Failed to create firewall: #{ex.message}".colorize(:red)
      STDERR.puts ex.response

      exit 1
    end
  end

  private def find_firewall
    firewalls = FirewallsList.from_json(hetzner_client.get("/firewalls")).firewalls

    firewalls.find do |firewall|
      firewall.name == firewall_name
    end
  end

  private def firewall_config
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
