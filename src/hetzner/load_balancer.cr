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

  def public_ipv6_address : String?
    public_net.try(&.ipv6).try(&.ip)
  end

  def private_ip_address : String?
    private_net.first?.try(&.ip).presence || public_ip_address || public_ipv6_address
  end

  # The API always sends `enabled` for load balancers; a missing value is treated as enabled, as
  # before the field was read.
  def public_interface_enabled? : Bool
    public_net.try { |net| net.enabled != false } || false
  end

  # A disabled public interface must never be handed out, so there is no public fallback then.
  def ip_address(prefer_private : Bool) : String?
    return private_net.first?.try(&.ip).presence unless public_interface_enabled?

    prefer_private ? private_ip_address : (public_ip_address || public_ipv6_address)
  end

  def attached_to_network?(network_id) : Bool
    private_net.any? { |net| net.network == network_id }
  end

  # Why the load balancer cannot be (or stay) reachable only via the private network, if anything.
  def private_only_error(network_id) : String?
    unless attached_to_network?(network_id)
      return "The load balancer is not attached to the configured private network. Attach it in the Hetzner console (or delete it so that it can be recreated), then run create again."
    end

    unless targets.all? { |target| target.use_private_ip == true }
      "The load balancer has targets that do not use private IPs, which prevents making it reachable only via the private network. Remove them or switch them to private IPs in the Hetzner console, then run create again."
    end
  end
end
