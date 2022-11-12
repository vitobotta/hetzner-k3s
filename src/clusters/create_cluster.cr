require "../configuration/main"
require "../hetzner/placement_group"
require "../hetzner/ssh_key"
require "../hetzner/firewall"

class Clusters::CreateCluster
  private getter configuration : Configuration::Main
  private getter placement_group : Hetzner::PlacementGroup | Nil
  private getter placement_groups : Hash(String, Hetzner::PlacementGroup | String) = Hash(String, Hetzner::PlacementGroup | String).new
  private property ssh_key : Hetzner::SSHKey | String?
  private property firewall : Hetzner::Firewall | String?

  def initialize(@configuration)
  end

  def run
    create_masters
  end

  private def create_masters
    # p placement_group("masters")
    # p ssh_key
    p firewall
  end

  private def placement_group(node_pool)
    placement_groups[node_pool] ||= Hetzner::PlacementGroup.create(
      hetzner_client = configuration.hetzner_client,
      placement_group_name = "#{configuration.cluster_name}-#{node_pool}"
    )
  end

  private def ssh_key
    @ssh_key ||= Hetzner::SSHKey.create(
      hetzner_client = configuration.hetzner_client,
      ssh_key_name = configuration.cluster_name,
      public_ssh_key_path = configuration.public_ssh_key_path.not_nil!
    )
  end

  private def firewall
    @firewall ||= Hetzner::Firewall.create(
      hetzner_client = configuration.hetzner_client,
      firewall_name = configuration.cluster_name,
      ssh_allowed_networks = configuration.ssh_allowed_networks,
      api_allowed_networks = configuration.api_allowed_networks,
      high_availability = configuration.masters_pool.not_nil!.instance_count.not_nil!  > 1
    )
  end
end
