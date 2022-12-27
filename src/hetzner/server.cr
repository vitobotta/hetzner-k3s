require "json"
require "./public_net"

class Hetzner::Server
  include JSON::Serializable

  property id : Int32
  property name : String
  getter public_net : PublicNet?

  def ip_address
    public_net.try(&.ipv4).try(&.ip)
  end
end
