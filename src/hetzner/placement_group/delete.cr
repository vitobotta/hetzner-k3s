require "../client"
require "./find"
require "../../util"

class Hetzner::PlacementGroup::Delete
  include Util

  getter hetzner_client : Hetzner::Client
  getter placement_group_name : String
  getter placement_group_finder : Hetzner::PlacementGroup::Find

  def initialize(@hetzner_client, @placement_group_name)
    @placement_group_finder = Hetzner::PlacementGroup::Find.new(@hetzner_client, @placement_group_name)
  end

  def run
    placement_group = placement_group_finder.run

    return handle_missing_placement_group unless placement_group

    log_line "Deleting placement group #{placement_group_name}..."
    delete_placement_group(placement_group.id)
    log_line "...placement group #{placement_group_name} deleted"

    placement_group_name
  end

  private def handle_missing_placement_group
    log_line "Placement group #{placement_group_name} does not exist, skipping delete"
    placement_group_name
  end

  private def delete_placement_group(placement_group_id)
    Retriable.retry(max_attempts: 10, backoff: false, base_interval: 5.seconds) do
      success, response = hetzner_client.delete("/placement_groups", placement_group_id)

      unless success
        STDERR.puts "[#{default_log_prefix}] Failed to delete placement group: #{response}"
        STDERR.puts "[#{default_log_prefix}] Retrying to delete placement group in 5 seconds..."
        raise "Failed to delete placement group"
      end
    end
  end

  private def default_log_prefix
    "Placement group"
  end
end
