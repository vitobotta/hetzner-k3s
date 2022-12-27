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
      puts "Deleting firewall...".colorize(:magenta)

      hetzner_client.delete("/firewalls", firewall.id)

      puts "...firewall deleted.\n".colorize(:magenta)
    else
      puts "firewall does not exist, skipping.\n".colorize(:magenta)
    end

    firewall_name

  rescue ex : Crest::RequestFailed
    STDERR.puts "Failed to delete firewall: #{ex.message}".colorize(:red)
    STDERR.puts ex.response

    exit 1
  end
end
