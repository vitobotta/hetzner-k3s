require "../configuration/main"
require "../configuration/loader"
require "../hetzner/client"
require "../hetzner/placement_group/create"
require "../hetzner/ssh_key/create"
require "../hetzner/firewall/create"
require "../hetzner/network/create"
require "../hetzner/server/create"
require "../hetzner/load_balancer/create"

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
  private property server_creators : Array(Hetzner::Server::Create) = [] of Hetzner::Server::Create

  def initialize(@configuration)
    @network = find_network.not_nil!

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
    create_servers

    create_load_balancer if settings.masters_pool.instance_count > 1
  end

  private def initialize_masters
    masters_pool = settings.masters_pool

    placement_group = Hetzner::PlacementGroup::Create.new(
      hetzner_client: hetzner_client,
      placement_group_name: "#{settings.cluster_name}-masters"
    ).run

    masters_pool.instance_count.times do |i|
      instance_type = masters_pool.instance_type
      master_name = "#{settings.cluster_name}-#{instance_type}-master#{i + 1}"

      server_creators << Hetzner::Server::Create.new(
        hetzner_client: hetzner_client,
        cluster_name: settings.cluster_name,
        server_name: master_name,
        instance_type: instance_type,
        image: settings.image,
        location: masters_pool.location,
        placement_group: placement_group,
        ssh_key: ssh_key,
        firewall: firewall,
        network: network,
        additional_packages: settings.additional_packages,
        additional_post_create_commands: settings.post_create_commands
      )
    end
  end

  private def initialize_worker_nodes
    settings.worker_node_pools.each do |node_pool|
      placement_group = Hetzner::PlacementGroup::Create.new(
        hetzner_client: hetzner_client,
        placement_group_name: "#{settings.cluster_name}-#{node_pool.name}"
      ).run

      node_pool.instance_count.times do |i|
        instance_type = node_pool.instance_type
        node_name = "#{settings.cluster_name}-#{node_pool.name}-#{instance_type}-worker#{i + 1}"

        server_creators << Hetzner::Server::Create.new(
          hetzner_client: hetzner_client,
          cluster_name: settings.cluster_name,
          server_name: node_name,
          instance_type: instance_type,
          image: settings.image,
          location: node_pool.location,
          placement_group: placement_group,
          ssh_key: ssh_key,
          firewall: firewall,
          network: network,
          additional_packages: settings.additional_packages,
          additional_post_create_commands: settings.post_create_commands
        )
      end
    end
  end

  private def create_load_balancer
    Hetzner::LoadBalancer::Create.new(
      hetzner_client: hetzner_client,
      load_balancer_name: settings.cluster_name,
      location: configuration.masters_location,
      network_id: network.id
    ).run
  end

  private def create_servers
    initialize_masters
    initialize_worker_nodes

    channel = Channel(Hetzner::Server).new

    server_creators.each do |server_creator|
      spawn do
        server = server_creator.run
        channel.send(server)
      end
    end

    server_creators.size.times do
      servers << channel.receive
    end

    servers.each { |server| p server.ip_address }
  end

  private def find_network
    existing_network_name = settings.existing_network

    if existing_network_name
      Hetzner::Network::Find.new(hetzner_client, existing_network_name).run
    else
      Hetzner::Network::Create.new(
        hetzner_client: hetzner_client,
        network_name: settings.cluster_name,
        location: settings.masters_pool.location
      ).run
    end
  end
end
