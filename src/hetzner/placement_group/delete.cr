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
    if placement_group = placement_group_finder.run
      log_line "Deleting placement group #{placement_group_name}..."

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
