require "json"

class Hetzner::Network
  include JSON::Serializable

  property id : Int32
  property name : String
end
