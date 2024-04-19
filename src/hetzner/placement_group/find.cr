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
    response = hetzner_client.get("/placement_groups", { :name => placement_group_name })
    PlacementGroupsList.from_json(response).placement_groups
  rescue ex : Crest::RequestFailed
    STDERR.puts "[#{default_log_prefix}] Failed to fetch placement groups: #{ex.message}"
    exit 1
  end

  private def default_log_prefix
    "Placement groups"
  end
end
