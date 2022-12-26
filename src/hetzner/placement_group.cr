require "./client"
require "./placement_groups_list"

class Hetzner::PlacementGroup
  include JSON::Serializable

  property id : Int32
  property name : String

  def self.create(hetzner_client, placement_group_name)
    puts

    begin
      if placement_group = find(hetzner_client, placement_group_name)
        puts "Placement group #{placement_group_name} already exists, skipping.\n".colorize(:blue)
      else
        puts "Creating placement group #{placement_group_name}...".colorize(:blue)

        placement_group_config = {
          "name" => placement_group_name,
          "type" => "spread"
        }

        hetzner_client.post("/placement_groups", placement_group_config)
        puts "...placement group created.\n".colorize(:blue)

        placement_group = find(hetzner_client, placement_group_name)
      end

      placement_group.not_nil!

    rescue ex : Crest::RequestFailed
      STDERR.puts "Failed to create placement group #{placement_group_name}: #{ex.message}".colorize(:red)
      STDERR.puts ex.response

      exit 1
    end
  end

  private def self.find(hetzner_client, placement_group_name)
    placement_groups = PlacementGroupsList.from_json(hetzner_client.get("/placement_groups")).placement_groups

    placement_groups.find do |placement_group|
      placement_group.name == placement_group_name
    end
  end
end
