require "./firewall"

class Hetzner::FirewallsList
  include JSON::Serializable

  property firewalls : Array(Hetzner::Firewall)
end
