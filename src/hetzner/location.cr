require "./client"

class Hetzner::Location
  include JSON::Serializable

  property id : Int32
  property name : String
end
