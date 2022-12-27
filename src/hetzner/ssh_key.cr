require "json"

class Hetzner::SSHKey
  include JSON::Serializable

  property id : Int32
  property name : String
  property fingerprint : String
end
