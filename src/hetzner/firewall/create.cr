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
  getter ssh_port : Int32

  def initialize(
      @hetzner_client,
      @firewall_name,
      @ssh_allowed_networks,
      @api_allowed_networks,
      @high_availability,
      @private_network_subnet,
      @ssh_port
    )
    @firewall_finder = Hetzner::Firewall::Find.new(hetzner_client, firewall_name)
  end

  def run
    firewall = firewall_finder.run

    if firewall
      print "Updating firewall..."
      action_path = "/firewalls/#{firewall.id}/actions/set_rules"
    else
      print "Creating firewall..."
      action_path = "/firewalls"
    end

    begin
      hetzner_client.post(action_path, firewall_config)
      puts "done."
    rescue ex : Crest::RequestFailed
      STDERR.puts "Failed to create or update firewall: #{ex.message}"
      STDERR.puts ex.response
      exit 1
    end

    firewall = firewall_finder.run
    firewall.not_nil!
  end

  private def firewall_config
    rules = [
      {
        description: "Allow SSH port",
        direction: "in",
        protocol: "tcp",
        port: ssh_port.to_s,
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
