require "../client"
require "./find"
require "../../util"

class Hetzner::PlacementGroup::Create
  include Util

  private getter settings : Configuration::Main
  private getter hetzner_client : Hetzner::Client
  private getter placement_group_name : String
  private getter labels : Hash(String, String)
  private getter placement_group_finder : Hetzner::PlacementGroup::Find

  def initialize(@settings, @hetzner_client, @placement_group_name, @labels = {} of String => String)
    @placement_group_finder = Hetzner::PlacementGroup::Find.new(@hetzner_client, @placement_group_name)
  end

  def run
    placement_group = placement_group_finder.run

    return placement_group if placement_group

    log_line "Creating placement group #{placement_group_name}..."
    create_placement_group
    log_line "...placement group #{placement_group_name} created"
    placement_group_finder.run.not_nil!
  end

  private def create_placement_group
    Retriable.retry(max_attempts: 10, backoff: false, base_interval: 5.seconds) do
      success, response = hetzner_client.post("/placement_groups", placement_group_config)

      unless success
        STDERR.puts "[#{default_log_prefix}] Failed to create placement group: #{response}"
        STDERR.puts "[#{default_log_prefix}] Retrying to create placement group in 5 seconds..."
        raise "Failed to create placement group"
      end
    end
  end

  private def placement_group_config
    {
      :name   => placement_group_name,
      :type   => "spread",
      :labels => labels,
    }
  end

  private def default_log_prefix
    "Placement group"
  end
end
