require "../client"
require "./find"

class Hetzner::PlacementGroup::Create
  getter hetzner_client : Hetzner::Client
  getter placement_group_name : String
  getter placement_group_finder : Hetzner::PlacementGroup::Find

  def initialize(@hetzner_client, @placement_group_name)
    @placement_group_finder = Hetzner::PlacementGroup::Find.new(@hetzner_client, @placement_group_name)
  end

  def run
    puts

    begin
      if placement_group = placement_group_finder.run
        puts "Placement group #{placement_group_name} already exists, skipping.\n"
      else
        puts "Creating placement group #{placement_group_name}..."

        placement_group_config = {
          "name" => placement_group_name,
          "type" => "spread"
        }

        hetzner_client.post("/placement_groups", placement_group_config)
        puts "...placement group created.\n"

        placement_group = placement_group_finder.run
      end

      placement_group.not_nil!

    rescue ex : Crest::RequestFailed
      STDERR.puts "Failed to create placement group #{placement_group_name}: #{ex.message}"
      STDERR.puts ex.response

      exit 1
    end
  end
end
