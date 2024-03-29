require "../client"
require "./find"

class Hetzner::PlacementGroup::Delete
  getter hetzner_client : Hetzner::Client
  getter placement_group_name : String
  getter placement_group_finder : Hetzner::PlacementGroup::Find

  def initialize(@hetzner_client, @placement_group_name)
    @placement_group_finder = Hetzner::PlacementGroup::Find.new(@hetzner_client, @placement_group_name)
  end

  def run
    if placement_group = placement_group_finder.run
      print "Deleting placement group #{placement_group_name}..."

      hetzner_client.delete("/placement_groups", placement_group.id)

      puts "done."
    else
      puts "Placement group #{placement_group_name} does not exist, skipping."
    end

    placement_group_name

  rescue ex : Crest::RequestFailed
    STDERR.puts "Failed to delete placement group: #{ex.message}"
    STDERR.puts ex.response

    exit 1
  end
end
