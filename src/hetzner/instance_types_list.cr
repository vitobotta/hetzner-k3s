require "./instance_type"

class Hetzner::InstanceTypesList
  include JSON::Serializable

  property server_types : Array(Hetzner::InstanceType)
end
