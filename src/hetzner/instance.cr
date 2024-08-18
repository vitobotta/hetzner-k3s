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

  def public_ip_address
    public_net.try(&.ipv4).try(&.ip)
  end

  def private_ip_address
    net = private_net

    return public_ip_address unless net
    return if net.try(&.empty?)

    net[0].ip
  end

  def host_ip_address
    if public_ip_address.nil?
      private_ip_address
    else
      public_ip_address
    end
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
