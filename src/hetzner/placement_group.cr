require "./client"

class Hetzner::PlacementGroup
  include JSON::Serializable

  property id : Int32?
  property name : String?

  @[YAML::Field(key: "hetzner_client", ignore: true)]
  private getter hetzner_client : Hetzner::Client

  @[YAML::Field(key: "placement_group_name", ignore: true)]
  private getter placement_group_name : String

  def initialize(@hetzner_client, @placement_group_name)
  end

  def create
    puts

    if p placement_group = find_placement_group
      puts "Placement group #{placement_group_name} already exists, skipping.\n"
      return
    end

    # puts "Creating placement group #{placement_group_name}..."

    # begin
    #   placement_group = hetzner_client.post("/placement_groups", placement_group_config)

    #   puts "...done.\n"

    #   placement_group
    # rescue ex : Crest::RequestFailed
    #   STDERR.puts "Failed to create placement group #{placement_group_name}: #{ex.message}"
    #   exit 1
    # end
  end

  private def find_placement_group
    # p hetzner_client.get("/placement_groups")

    # ["placement_groups"].find do |placement_group|
    #   placement_group["name"] == placement_group_name
    # end
  end

  private def placement_group_config
    {
      name: placement_group_name,
      type: "spread"
    }
  end
end
