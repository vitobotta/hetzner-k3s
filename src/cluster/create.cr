require "../configuration/main"
require "../configuration/loader"
require "../hetzner/client"
require "../hetzner/placement_group/create"
require "../hetzner/ssh_key/create"
require "../hetzner/firewall/create"
require "../hetzner/network/create"
require "../hetzner/server/create"

class Cluster::Create
  private getter configuration : Configuration::Loader
  private getter hetzner_client : Hetzner::Client do
    configuration.hetzner_client
  end
  private getter settings : Configuration::Main do
    configuration.settings
  end
  private getter public_ssh_key_path : String do
    configuration.public_ssh_key_path
  end
  private getter network : Hetzner::Network
  private getter firewall : Hetzner::Firewall
  private getter ssh_key : Hetzner::SSHKey
  private getter placement_groups : Hash(String, Hetzner::PlacementGroup?) = Hash(String, Hetzner::PlacementGroup?).new
  private property servers : Array(Hetzner::Server) = [] of Hetzner::Server

  def initialize(@configuration)
    @network = Hetzner::Network::Create.new(
      hetzner_client: hetzner_client,
      network_name: settings.cluster_name,
      location: settings.masters_pool.location
    ).run

    @firewall = Hetzner::Firewall::Create.new(
      hetzner_client: hetzner_client,
      firewall_name: settings.cluster_name,
      ssh_allowed_networks: settings.ssh_allowed_networks,
      api_allowed_networks: settings.api_allowed_networks,
      high_availability: settings.masters_pool.instance_count > 1
    ).run

    @ssh_key = Hetzner::SSHKey::Create.new(
      hetzner_client: hetzner_client,
      ssh_key_name: settings.cluster_name,
      public_ssh_key_path: public_ssh_key_path
    ).run
  end

  def run
    create_masters
  end

  private def create_masters
    channel = Channel(Hetzner::Server).new

    masters_pool = settings.masters_pool

    placement_group = Hetzner::PlacementGroup::Create.new(
      hetzner_client: hetzner_client,
      placement_group_name: "#{settings.cluster_name}-masters"
    ).run

    masters_pool.instance_count.times do |i|
      instance_type = masters_pool.instance_type
      master_name = "#{settings.cluster_name}-#{instance_type}-master#{i + 1}"

      spawn do
        server = Hetzner::Server::Create.new(
          hetzner_client: hetzner_client,
          cluster_name: settings.cluster_name,
          server_name: master_name,
          instance_type: masters_pool.instance_type,
          image: settings.image,
          location: masters_pool.location,
          placement_group: placement_group,
          ssh_key: ssh_key,
          firewall: firewall,
          network: network,
          additional_packages: settings.additional_packages,
          additional_post_create_commands: settings.post_create_commands
        ).run

        channel.send(server)
      end
    end

    masters_pool.instance_count.times do
      servers << channel.receive
    end

    servers.each { |server| p server.ip_address }
  end
end
