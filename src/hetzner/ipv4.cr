require "./client"

class Hetzner::Ipv4
  include JSON::Serializable

  property ip : String?
end
