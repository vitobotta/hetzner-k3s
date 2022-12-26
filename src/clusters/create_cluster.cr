require "../configuration/main"
require "../hetzner/placement_group"
require "../hetzner/ssh_key"
require "../hetzner/firewall"
require "../hetzner/network"
require "../hetzner/server"

class Clusters::CreateCluster
  private getter configuration : Configuration::Main
  private getter network : Hetzner::Network
  private getter firewall : Hetzner::Firewall
  private getter ssh_key : Hetzner::SSHKey
  private getter placement_groups : Hash(String, Hetzner::PlacementGroup?) = Hash(String, Hetzner::PlacementGroup?).new
  private property servers : Array(Hetzner::Server) = [] of Hetzner::Server


  def initialize(@configuration)
    @network = Hetzner::Network.create(
      hetzner_client: configuration.hetzner_client,
      network_name: configuration.cluster_name,
      location: configuration.masters_pool.location
    )

    @firewall = Hetzner::Firewall.create(
      hetzner_client: configuration.hetzner_client,
      firewall_name: configuration.cluster_name,
      ssh_allowed_networks: configuration.ssh_allowed_networks,
      api_allowed_networks: configuration.api_allowed_networks,
      high_availability: configuration.masters_pool.instance_count > 1
    )

    @ssh_key = Hetzner::SSHKey.create(
      hetzner_client: configuration.hetzner_client,
      ssh_key_name: configuration.cluster_name,
      public_ssh_key_path: configuration.public_ssh_key_path
    )
  end

  def run
    create_masters
  end

  private def create_masters
    channel = Channel(String).new

    masters_pool = configuration.masters_pool

    placement_group = Hetzner::PlacementGroup.create(
      hetzner_client = configuration.hetzner_client,
      placement_group_name = "#{configuration.cluster_name}-masters"
    )

    masters_pool.instance_count.times do |i|
      instance_type = masters_pool.instance_type
      master_name = "#{configuration.cluster_name}-#{instance_type}-master#{i + 1}"

      spawn do
        servers << Hetzner::Server.create(
          hetzner_client: configuration.hetzner_client,
          server_name: master_name,
          instance_type: masters_pool.instance_type,
          image: configuration.image,
          location: masters_pool.location,
          placement_group: placement_group,
          ssh_key: ssh_key,
          firewall: firewall,
          network: network,
          additional_packages: configuration.additional_packages,
          additional_post_create_commands: configuration.post_create_commands
        )

        channel.send(master_name)
      end
    end

    masters_pool.instance_count.times do
      channel.receive
    end

    Fiber.yield

    p servers.each { |server| server.ip_address }
  end
end
