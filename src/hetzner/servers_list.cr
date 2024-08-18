require "./instance"

class Hetzner::InstancesList
  include JSON::Serializable

  property instances : Array(Hetzner::Instance)
end
