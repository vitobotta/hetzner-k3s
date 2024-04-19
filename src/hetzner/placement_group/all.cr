require "../client"
require "../placement_group"
require "../placement_groups_list"

class Hetzner::PlacementGroup::All
  getter hetzner_client : Hetzner::Client

  def initialize(@hetzner_client)
  end

  def run : Array(Hetzner::PlacementGroup)
    fetch_placement_groups
  end

  def delete_unused
    all_placement_groups = fetch_placement_groups

    all_placement_groups.reject! do |placement_group|
      if placement_group.servers.size == 0
        Hetzner::PlacementGroup::Delete.new(hetzner_client, placement_group: placement_group ).run
        true
      else
        false
      end
    end

    all_placement_groups
  end

  def delete_all
    fetch_placement_groups.each do |placement_group|
      Hetzner::PlacementGroup::Delete.new(hetzner_client, placement_group: placement_group ).run
    end
  end

  private def fetch_placement_groups
    response = hetzner_client.get("/placement_groups", { :per_page => 100 })
    PlacementGroupsList.from_json(response).placement_groups
  rescue ex : Crest::RequestFailed
    STDERR.puts "[#{default_log_prefix}] Failed to fetch placement groups: #{ex.message}"
    exit 1
  end

  private def default_log_prefix
    "Placement groups"
  end
end
