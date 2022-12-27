require "../client"
require "./find"

class Hetzner::Firewall::Delete
  getter hetzner_client : Hetzner::Client
  getter firewall_name : String
  getter firewall_finder : Hetzner::Firewall::Find

  def initialize(@hetzner_client, @firewall_name)
    @firewall_finder = Hetzner::Firewall::Find.new(@hetzner_client, @firewall_name)
  end

  def run
    if firewall = firewall_finder.run
      puts "Deleting firewall #{firewall_name}...".colorize(:magenta)

      hetzner_client.delete("/firewalls", firewall.id)

      puts "...firewall #{firewall_name} deleted.\n".colorize(:magenta)
    else
      puts "firewall #{firewall_name} does not exist, skipping.\n".colorize(:magenta)
    end

  rescue ex : Crest::RequestFailed
    STDERR.puts "Failed to delete firewall: #{ex.message}".colorize(:red)
    STDERR.puts ex.response

    exit 1
  end
end
