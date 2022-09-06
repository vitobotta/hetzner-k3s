require "./client"

class Hetzner::ServerType
  include JSON::Serializable

  property id : Int32?
  property name : String?
end
