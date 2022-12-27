require "../client"
require "../firewall"
require "../firewalls_list"

class Hetzner::Firewall::Find
  getter hetzner_client : Hetzner::Client
  getter firewall_name : String

  def initialize(@hetzner_client, @firewall_name)
  end

  def run
    firewalls = FirewallsList.from_json(hetzner_client.get("/firewalls")).firewalls

    firewalls.find do |firewall|
      firewall.name == firewall_name
    end
  end
end
