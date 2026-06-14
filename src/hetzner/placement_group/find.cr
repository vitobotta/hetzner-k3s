require "../client"
require "../placement_group"
require "../placement_groups_list"

class Hetzner::PlacementGroup::Find
  private getter hetzner_client : Hetzner::Client
  private getter placement_group_name : String

  def initialize(@hetzner_client, @placement_group_name)
  end

  def run
    fetch_placement_groups.find { |placement_group| placement_group.name == placement_group_name }
  end

  private def fetch_placement_groups
    Retriable.retry(max_attempts: 10, backoff: false, base_interval: 5.seconds) do
      success, response = hetzner_client.get("/placement_groups")

      if success
        PlacementGroupsList.from_json(response).placement_groups
      else
        STDERR.puts "[#{default_log_prefix}] Failed to fetch placement groups: #{response}"
        STDERR.puts "[#{default_log_prefix}] Retrying to fetch placement groups in 5 seconds..."
        raise "Failed to fetch placement groups"
      end
    end
  end

  private def default_log_prefix
    "Placement group"
  end
end
