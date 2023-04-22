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
    firewall = firewall_finder.run

    if firewall
      print "Deleting firewall..."
      delete_firewall(firewall.id)
      puts "done."
    else
      puts "firewall does not exist, skipping."
    end

    firewall_name
  end

  private def delete_firewall(firewall_id)
    hetzner_client.delete("/firewalls", firewall_id)
  rescue ex : Crest::RequestFailed
    STDERR.puts "Failed to delete firewall: #{ex.message}"
    STDERR.puts ex.response
    exit 1
  end
end
