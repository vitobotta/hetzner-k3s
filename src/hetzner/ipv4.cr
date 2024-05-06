require "./client"

class Hetzner::Ipv4
  include JSON::Serializable

  property ip : String?

  def initialize(ip : String)
    @ip = ip
  end
end
