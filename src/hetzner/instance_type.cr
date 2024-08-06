require "./client"

class Hetzner::InstanceType
  include JSON::Serializable

  property id : Int32
  property name : String
end
