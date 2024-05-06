require "json"

class Hetzner::NetworkInterface
  include JSON::Serializable

  property ip : String?

  def initialize(ip : String)
    @ip = ip
  end
end
