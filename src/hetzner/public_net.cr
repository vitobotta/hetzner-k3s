require "json"
require "./ipv4"
require "./ipv6"

class Hetzner::PublicNet
  include JSON::Serializable

  property enabled : Bool?
  property ipv4 : Hetzner::Ipv4?
  property ipv6 : Hetzner::Ipv6?

  def initialize(ipv4 : String) : Hetzner::Ipv4
    @ipv4 = Hetzner::Ipv4.new(ipv4)
  end
end
