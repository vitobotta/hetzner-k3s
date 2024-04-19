require "json"

class Hetzner::Network
  include JSON::Serializable

  property id : Int64
  property name : String
end
