require "../client"
require "../firewall"
require "../firewalls_list"

class Hetzner::Firewall::Find
  getter hetzner_client : Hetzner::Client
  getter firewall_name : String

  def initialize(@hetzner_client, @firewall_name)
  end

  def run
    firewalls = fetch_firewalls

    firewalls.find { |firewall| firewall.name == firewall_name }
  end

  private def fetch_firewalls
    FirewallsList.from_json(hetzner_client.get("/firewalls")).firewalls
  rescue ex : Crest::RequestFailed
    STDERR.puts "Failed to fetch firewalls: #{ex.message}"
    STDERR.puts ex.response
    [] of Firewall
  end
end
