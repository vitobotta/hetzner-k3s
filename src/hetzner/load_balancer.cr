require "json"
require "./public_net"

class Hetzner::LoadBalancer
  include JSON::Serializable

  class Target
    include JSON::Serializable

    property use_private_ip : Bool?
  end

  property id : Int32
  property name : String
  property private_net : Array(Hetzner::Ipv4)
  property targets : Array(Target) = [] of Target
  getter public_net : PublicNet?

  def public_ip_address : String?
    public_net.try(&.ipv4).try(&.ip)
  end

  def private_ip_address : String?
    private_net.first?.try(&.ip).presence || public_ip_address
  end

  def public_interface_enabled? : Bool
    public_net.try(&.enabled) == true
  end

  # A disabled public interface must never be handed out, so there is no public fallback then.
  def ip_address(prefer_private : Bool) : String?
    return private_net.first?.try(&.ip).presence unless public_interface_enabled?

    prefer_private ? private_ip_address : public_ip_address
  end

  def attached_to_network?(network_id) : Bool
    private_net.any? { |net| net.network == network_id }
  end
end
