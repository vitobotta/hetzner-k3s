require "json"

class Hetzner::Ipv6
  include JSON::Serializable

  property ip : String?
  property blocked : Bool?

  def initialize(ip : String)
    @ip = ip
  end
end
