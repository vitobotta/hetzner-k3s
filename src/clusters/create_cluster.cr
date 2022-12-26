require "../configuration/main"
require "../hetzner/placement_group"
require "../hetzner/ssh_key"
require "../hetzner/firewall"
require "../hetzner/network"
require "../hetzner/server"

class Clusters::CreateCluster
  private getter configuration : Configuration::Main
  private getter placement_groups : Hash(String, Hetzner::PlacementGroup?) = Hash(String, Hetzner::PlacementGroup?).new
  private property ssh_key : Hetzner::SSHKey?
  private property firewall : Hetzner::Firewall?
  private property network : Hetzner::Network?
  property servers : Array(Hetzner::Server) = [] of Hetzner::Server

  def initialize(@configuration)
  end

  def run
    create_masters
  end

  private def create_masters
    masters_pool = configuration.masters_pool.not_nil!

    masters_pool.instance_count.not_nil!.times do |i|
      instance_type = masters_pool.instance_type.not_nil!
      master_name = "#{configuration.cluster_name}-#{instance_type}-master#{i+1}"

      servers << Hetzner::Server.create(
        hetzner_client = configuration.hetzner_client,
        server_name = master_name,
        instance_type = masters_pool.instance_type,
        image = configuration.image,
        location = masters_pool.location,
        ssh_key = create_ssh_key.not_nil!,
        firewall = create_firewall.not_nil!,
        placement_group = create_placement_group("masters").not_nil!,
        network = create_network.not_nil!,
        additional_packages = configuration.additional_packages,
        additional_post_create_commands = configuration.post_create_commands
      ).not_nil!

      p servers.first
    end
  end

  private def create_placement_group(node_pool)
    placement_groups[node_pool] ||= Hetzner::PlacementGroup.create(
      hetzner_client = configuration.hetzner_client,
      placement_group_name = "#{configuration.cluster_name}-#{node_pool}"
    )
  end

  private def create_ssh_key
    @ssh_key ||= Hetzner::SSHKey.create(
      hetzner_client = configuration.hetzner_client,
      ssh_key_name = configuration.cluster_name,
      public_ssh_key_path = configuration.public_ssh_key_path.not_nil!
    )
  end

  private def create_firewall
    @firewall ||= Hetzner::Firewall.create(
      hetzner_client = configuration.hetzner_client,
      firewall_name = configuration.cluster_name,
      ssh_allowed_networks = configuration.ssh_allowed_networks,
      api_allowed_networks = configuration.api_allowed_networks,
      high_availability = configuration.masters_pool.not_nil!.instance_count.not_nil! > 1
    )
  end

  private def create_network
    @network ||= Hetzner::Network.create(
      hetzner_client = configuration.hetzner_client,
      network_name = configuration.cluster_name,
      location = configuration.masters_pool.not_nil!.location.not_nil!
    )
  end
end
