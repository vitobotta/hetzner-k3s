require "./client"

class Hetzner::LocationsList
  include JSON::Serializable

  property locations : Array(Hetzner::Location)
end
