require "json"

class Hetzner::Network
  class Subnet
    include JSON::Serializable

    property network_zone : String
    property type : String
    property ip_range : String
    property gateway : String?
  end

  include JSON::Serializable

  property id : Int64
  property name : String
  property subnets : Array(Subnet) = [] of Subnet

  def network_zone : String?
    subnets.first?.try(&.network_zone)
  end
end
