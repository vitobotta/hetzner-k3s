require "./instance"

class Hetzner::InstancesList
  include JSON::Serializable

  property servers : Array(Hetzner::Instance)
end
