require "./location"

class Hetzner::LocationsList
  include JSON::Serializable

  property locations : Array(Hetzner::Location)
end
