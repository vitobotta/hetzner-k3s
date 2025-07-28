require "json"
require "./public_net"

class Hetzner::LoadBalancer
  include JSON::Serializable

  property id : Int32
  property name : String
  property private_net : Array(Hetzner::Ipv4)
  getter public_net : PublicNet?

  def public_ip_address : String?
    public_net.try(&.ipv4).try(&.ip)
  end

  def private_ip_address : String?
    private_net.first?.try(&.ip) || public_ip_address
  end
end
