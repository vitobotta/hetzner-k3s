require "json"
require "./public_net"
require "./network_interface"

class Hetzner::Instance
  include JSON::Serializable

  property id : Int32
  property name : String
  property status : String
  getter public_net : PublicNet?
  getter private_net : Array(Hetzner::NetworkInterface)?

  def public_ip_address : String?
    public_net.try(&.ipv4).try(&.ip)
  end

  def private_ip_address : String?
    private_net.try(&.first?).try(&.ip) || public_ip_address
  end

  def host_ip_address(prefer_private_ip : Bool = false) : String?
    private_ip = private_net.try(&.first?).try(&.ip)
    public_ip = public_ip_address
    prefer_private_ip ? (private_ip || public_ip) : (public_ip || private_ip)
  end

  def master?
    /-master\d+/ =~ name
  end

  def initialize(id : Int32, status : String, instance_name : String, internal_ip : String, external_ip : String)
    @id = id
    @status = status
    @name = instance_name
    @public_net = PublicNet.new(external_ip) unless external_ip.blank?
    @private_net = [NetworkInterface.new(internal_ip)] unless internal_ip.blank?
  end
end
