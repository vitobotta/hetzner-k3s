require "../client"
require "./find"
require "../../util"

class Hetzner::PlacementGroup::Delete
  include Util

  private getter hetzner_client : Hetzner::Client
  private getter deleting_unused = false

  def initialize(@hetzner_client, @placement_group_name : String? = nil, @placement_group : Hetzner::PlacementGroup? = nil)
    if placement_group_name = @placement_group_name
      placement_group_finder = Hetzner::PlacementGroup::Find.new(@hetzner_client, placement_group_name)
      placement_group = placement_group_finder.run
    elsif placement_group = @placement_group
      @placement_group_name = placement_group.name
    end

    @deleting_unused = placement_group_name.nil?
  end

  def run
    placement_group = @placement_group
    placement_group_name = @placement_group_name

    if placement_group
      if deleting_unused
        log_line "Deleting unused placement group #{placement_group_name}..."
      else
        log_line "Deleting placement group #{placement_group_name}..."
      end

      Retriable.retry(max_attempts: 10, backoff: false, base_interval: 5.seconds) do
        success, response = hetzner_client.delete("/placement_groups", placement_group.id)

        if success
          log_line "...placement group #{placement_group_name} deleted"
        else
          STDERR.puts "[#{default_log_prefix}] Failed to delete placement group #{placement_group_name}: #{response}"
          STDERR.puts "[#{default_log_prefix}] Retrying to delete placement group #{placement_group_name} in 5 seconds..."
          raise "Failed to delete placement group"
        end
      end
    else
      log_line "Placement group #{placement_group_name} does not exist, skipping delete"
    end

    placement_group_name
  end

  private def default_log_prefix
    "Placement groups"
  end
end
