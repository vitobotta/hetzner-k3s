require "../configuration/main"
require "../hetzner/placement_group"

class Clusters::CreateCluster
  private getter configuration : Configuration::Main
  private getter placement_group : Hetzner::PlacementGroup | Nil

  def initialize(@configuration)
  end

  def run
    placement_group = Hetzner::PlacementGroup.create(
      hetzner_client = configuration.hetzner_client,
      placement_group_name = "test"
    )
  end
end
