require "../configuration/main"
require "../configuration/loader"
require "../hetzner/client"
require "../hetzner/placement_group/create"
require "../hetzner/ssh_key/create"
require "../hetzner/firewall/create"
require "../hetzner/network/create"
require "../hetzner/server/create"
require "../hetzner/load_balancer/create"
require "../util/ssh"
require "../kubernetes/installer"
require "../util/ssh"

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
  private getter private_ssh_key_path : String do
    configuration.private_ssh_key_path
  end
  private getter masters : Array(Hetzner::Server) do
    servers.select { |server| server.master? }.sort_by(&.name)
  end
  private getter workers : Array(Hetzner::Server) do
    servers.select { |server| !server.master? }.sort_by(&.name)
  end
  private getter autoscaling_worker_node_pools : Array(Configuration::NodePool) do
    settings.worker_node_pools.select(&.autoscaling_enabled)
  end
  private getter kubernetes_installer : Kubernetes::Installer do
    Kubernetes::Installer.new(configuration, masters, workers, load_balancer, ssh, autoscaling_worker_node_pools)
  end
  private getter ssh : Util::SSH do
    Util::SSH.new(private_ssh_key_path, public_ssh_key_path)
  end

  private getter network : Hetzner::Network
  private getter firewall : Hetzner::Firewall
  private getter ssh_key : Hetzner::SSHKey
  private getter load_balancer : Hetzner::LoadBalancer?
  private getter placement_groups : Hash(String, Hetzner::PlacementGroup?) = Hash(String, Hetzner::PlacementGroup?).new
  private property servers : Array(Hetzner::Server) = [] of Hetzner::Server
  private property server_creators : Array(Hetzner::Server::Create) = [] of Hetzner::Server::Create

  def initialize(@configuration)
    puts "\n=== Creating infrastructure resources ===\n"

    @network = find_network.not_nil!

    @firewall = Hetzner::Firewall::Create.new(
      hetzner_client: hetzner_client,
      firewall_name: settings.cluster_name,
      ssh_allowed_networks: settings.ssh_allowed_networks,
      api_allowed_networks: settings.api_allowed_networks,
      high_availability: settings.masters_pool.instance_count > 1,
      private_network_subnet: settings.private_network_subnet
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

    kubernetes_installer.run
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
        snapshot_os: settings.snapshot_os,
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
    no_autoscaling_worker_node_pools = settings.worker_node_pools.reject(&.autoscaling_enabled)

    no_autoscaling_worker_node_pools.each do |node_pool|
      placement_group = Hetzner::PlacementGroup::Create.new(
        hetzner_client: hetzner_client,
        placement_group_name: "#{settings.cluster_name}-#{node_pool.name}"
      ).run

      node_pool.instance_count.times do |i|
        instance_type = node_pool.instance_type
        node_name = "#{settings.cluster_name}-#{instance_type}-pool-#{node_pool.name}-worker#{i + 1}"

        server_creators << Hetzner::Server::Create.new(
          hetzner_client: hetzner_client,
          cluster_name: settings.cluster_name,
          server_name: node_name,
          instance_type: instance_type,
          image: settings.image,
          snapshot_os: settings.snapshot_os,
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
    @load_balancer = Hetzner::LoadBalancer::Create.new(
      hetzner_client: hetzner_client,
      cluster_name: settings.cluster_name,
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

    servers.each do |server|
      spawn do
        ssh.wait_for_server server, settings.use_ssh_agent, "echo ready", "ready"
        channel.send(server)
      end
    end

    servers.size.times do
      channel.receive
    end
  end

  private def find_network
    existing_network_name = settings.existing_network

    if existing_network_name
      Hetzner::Network::Find.new(hetzner_client, existing_network_name).run
    else
      Hetzner::Network::Create.new(
        hetzner_client: hetzner_client,
        network_name: settings.cluster_name,
        location: settings.masters_pool.location,
        locations: configuration.locations,
        private_network_subnet: settings.private_network_subnet
      ).run
    end
  end
end
