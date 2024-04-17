require "../client"
require "./find"
require "../../util"

class Hetzner::PlacementGroup::Create
  include Util

  getter hetzner_client : Hetzner::Client
  getter placement_group_name : String
  getter placement_group_finder : Hetzner::PlacementGroup::Find

  def initialize(@hetzner_client, @placement_group_name)
    @placement_group_finder = Hetzner::PlacementGroup::Find.new(@hetzner_client, @placement_group_name)
  end

  def run
    placement_group = placement_group_finder.run

    if placement_group
      log_line "Placement group #{placement_group_name} already exists, skipping create"
    else
      log_line "Creating placement group #{placement_group_name}..."
      create_placement_group
      placement_group = placement_group_finder.run
      log_line "...placement group #{placement_group_name} created"
    end

    placement_group.not_nil!

  rescue ex : Crest::RequestFailed
    STDERR.puts "[#{default_log_prefix}] Failed to create placement group #{placement_group_name}: #{ex.message}"
    exit 1
  end

  private def create_placement_group
    hetzner_client.post("/placement_groups", placement_group_config)
  end

  private def placement_group_config
    {
      "name" => placement_group_name,
      "type" => "spread"
    }
  end

  private def default_log_prefix
    "Placement groups"
  end
end
