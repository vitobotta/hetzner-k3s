require "json"

class Hetzner::LoadBalancer
  include JSON::Serializable

  property id : Int32
  property name : String
end
