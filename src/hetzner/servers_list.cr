require "./server_type"

class Hetzner::ServersList
  include JSON::Serializable

  property servers : Array(Hetzner::Server)
end
