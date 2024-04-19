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

      if placement_group && placement_group.servers.any?
        log_line "Placement group #{placement_group_name} is not empty, skipping delete"
        return placement_group_name
      end

      hetzner_client.delete("/placement_groups", placement_group.id)

      log_line "...placement group #{placement_group_name} deleted"
    else
      log_line "Placement group #{placement_group_name} does not exist, skipping delete"
    end

    placement_group_name

  rescue ex : Crest::RequestFailed
    STDERR.puts "[#{default_log_prefix}] Failed to delete placement group: #{ex.message}"
    exit 1
  end

  private def default_log_prefix
    "Placement groups"
  end
end
