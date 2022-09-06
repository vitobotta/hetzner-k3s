require "./client"

class Hetzner::ServerTypesList
  include JSON::Serializable

  property server_types : Array(Hetzner::ServerType)
end
