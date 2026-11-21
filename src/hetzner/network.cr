require "json"

class Hetzner::Network
  # The API marks only network_zone as required on a subnet, and the zone is the only field
  # this tool reads. A required ip_range would reject a network the API returns happily, and
  # the project wide network listing decodes every network in the project at once.
  class Subnet
    include JSON::Serializable

    property network_zone : String
  end

  include JSON::Serializable

  property id : Int64
  property name : String
  property subnets : Array(Subnet) = [] of Subnet

  def network_zones : Array(String)
    subnets.map(&.network_zone)
  end
end
