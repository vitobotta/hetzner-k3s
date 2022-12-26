require "./client"
require "./ipv4"

class Hetzner::PublicNet
  include JSON::Serializable

  property ipv4 : Hetzner::Ipv4?
end
