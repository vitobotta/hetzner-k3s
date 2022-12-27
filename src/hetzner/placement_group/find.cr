require "../client"
require "../placement_group"
require "../placement_groups_list"

class Hetzner::PlacementGroup::Find
  getter hetzner_client : Hetzner::Client
  getter placement_group_name : String

  def initialize(@hetzner_client, @placement_group_name)
  end

  def run
    placement_groups = PlacementGroupsList.from_json(hetzner_client.get("/placement_groups")).placement_groups

    placement_groups.find do |placement_group|
      placement_group.name == placement_group_name
    end
  end
end
