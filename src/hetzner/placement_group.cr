require "json"

class Hetzner::PlacementGroup
  include JSON::Serializable

  property id : Int32
  property name : String
end
