require "json"

class Hetzner::NetworkInterface
  include JSON::Serializable

  property ip : String?
end
