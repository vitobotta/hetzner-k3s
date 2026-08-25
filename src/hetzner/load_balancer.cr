require "json"
require "./public_net"

class Hetzner::LoadBalancer
  include JSON::Serializable

  class Target
    include JSON::Serializable

    class LabelSelector
      include JSON::Serializable

      property selector : String?
    end

    property type : String?
    property use_private_ip : Bool?
    property label_selector : LabelSelector?
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
    private_net.first?.try(&.ip)
  end

  def public_interface_enabled? : Bool
    public_net.try(&.enabled) == true
  end

  def ip_address(prefer_private : Bool) : String?
    prefer_private || !public_interface_enabled? ? private_ip_address : public_ip_address
  end

  def attached_to_network?(network_id) : Bool
    private_net.any? { |net| net.network == network_id }
  end
end
