require "../client"
require "./find"

class Hetzner::Firewall::Create
  getter hetzner_client : Hetzner::Client
  getter firewall_name : String
  getter private_network_subnet : String
  getter ssh_allowed_networks : Array(String)
  getter api_allowed_networks : Array(String)
  getter high_availability : Bool
  getter firewall_finder : Hetzner::Firewall::Find

  def initialize(
      @hetzner_client,
      @firewall_name,
      @ssh_allowed_networks,
      @api_allowed_networks,
      @high_availability,
      @private_network_subnet
    )
    @firewall_finder = Hetzner::Firewall::Find.new(hetzner_client, firewall_name)
  end

  def run
    if firewall = firewall_finder.run
      print "Updating firewall..."

      hetzner_client.post("/firewalls/#{firewall.id}/actions/set_rules", firewall_config)

      puts "done."
    else
      print "Creating firewall..."

      hetzner_client.post("/firewalls", firewall_config)
      firewall = firewall_finder.run

      puts "done."
    end

    firewall.not_nil!

  rescue ex : Crest::RequestFailed
    STDERR.puts "Failed to create firewall: #{ex.message}"
    STDERR.puts ex.response

    exit 1
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
          private_network_subnet
        ],
        destination_ips: [] of String
      },
      {
        description: "Allow all UDP traffic between nodes on the private network",
        direction: "in",
        protocol: "udp",
        port: "any",
        source_ips: [
          private_network_subnet
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
