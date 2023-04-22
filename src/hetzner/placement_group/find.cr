require "../client"
require "../placement_group"
require "../placement_groups_list"

class Hetzner::PlacementGroup::Find
  getter hetzner_client : Hetzner::Client
  getter placement_group_name : String

  def initialize(@hetzner_client, @placement_group_name)
  end

  def run
    placement_groups = fetch_placement_groups

    placement_groups.find { |placement_group| placement_group.name == placement_group_name }
  end

  private def fetch_placement_groups
    PlacementGroupsList.from_json(hetzner_client.get("/placement_groups")).placement_groups
  rescue ex : Crest::RequestFailed
    STDERR.puts "Failed to fetch placement groups: #{ex.message}"
    STDERR.puts ex.response
    exit 1
  end
end
