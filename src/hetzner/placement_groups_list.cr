require "./placement_group"

class Hetzner::PlacementGroupsList
  include JSON::Serializable

  property placement_groups : Array(Hetzner::PlacementGroup)
end
