require "json"
require "./public_net"
require "./network_interface"

class Hetzner::Server
  include JSON::Serializable

  property id : Int32
  property name : String
  getter public_net : PublicNet?
  getter private_net : Array(Hetzner::NetworkInterface)?

  def public_ip_address
    public_net.try(&.ipv4).try(&.ip)
  end

  def private_ip_address
    net = private_net

    return unless net
    return if net.try(&.empty?)

    net[0].ip
  end
end
