require "json"

class Hetzner::PlacementGroup
  include JSON::Serializable
  include JSON::Serializable::Unmapped

  property id : Int32
  property name : String
  property servers : Array(Int64)
end
