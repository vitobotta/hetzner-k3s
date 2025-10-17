require "./instance_type"

class Hetzner::InstanceTypesList
  include JSON::Serializable

  property server_types : Array(Hetzner::InstanceType)
  property meta : Hetzner::Meta?
end

class Hetzner::Meta
  include JSON::Serializable

  property pagination : Hetzner::Pagination?
end

class Hetzner::Pagination
  include JSON::Serializable

  property page : Int32
  property per_page : Int32
  property total_entries : Int32
  property last_page : Int32
  property next_page : Int32?
  property previous_page : Int32?
end
