require "./firewall"

class Hetzner::NetworksList
  include JSON::Serializable

  property networks : Array(Hetzner::Network)
end
