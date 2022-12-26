require "./server"

class Hetzner::ServersList
  include JSON::Serializable

  property servers : Array(Hetzner::Server)
end
