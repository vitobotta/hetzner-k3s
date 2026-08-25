require "json"

class Hetzner::Ipv4
  include JSON::Serializable

  property ip : String?
  property network : Int64?

  def initialize(ip : String)
    @ip = ip
  end
end
