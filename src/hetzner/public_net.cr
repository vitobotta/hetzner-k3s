require "./client"
require "./ipv4"

class Hetzner::PublicNet
  include JSON::Serializable

  property ipv4 : Hetzner::Ipv4?

  def initialize(ipv4 : String) : Hetzner::Ipv4
    @ipv4 = Hetzner::Ipv4.new(ipv4)
  end
end
