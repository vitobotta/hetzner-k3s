require "../configuration/loader"
require "../hetzner/placement_group/delete"
require "../hetzner/ssh_key/delete"
require "../hetzner/firewall/delete"
require "../hetzner/network/delete"
require "../hetzner/server/delete"
require "../hetzner/load_balancer/delete"

class Cluster::Delete
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

  private property server_deletors : Array(Hetzner::Server::Delete) = [] of Hetzner::Server::Delete

  def initialize(@configuration)
  end

  def run
    puts "\n=== Deleting infrastructure resources ===\n"

    delete_resources
  end

  private def delete_resources
    delete_load_balancer
    delete_servers
    delete_placement_groups
    delete_network
    delete_firewall
    delete_ssh_key
  end

  private def delete_load_balancer
    Hetzner::LoadBalancer::Delete.new(
      hetzner_client: hetzner_client,
      cluster_name: settings.cluster_name
    ).run
  end

  private def delete_servers
    initialize_masters
    initialize_worker_nodes

    channel = Channel(String).new

    server_deletors.each do |server_deletor|
      spawn do
        server_deletor.run
        channel.send(server_deletor.server_name)
      end
    end

    server_deletors.size.times do
      channel.receive
    end
  end

  private def delete_placement_groups
    Hetzner::PlacementGroup::Delete.new(
      hetzner_client: hetzner_client,
      placement_group_name: "#{settings.cluster_name}-masters"
    ).run

    settings.worker_node_pools.each do |node_pool|
      Hetzner::PlacementGroup::Delete.new(
        hetzner_client: hetzner_client,
        placement_group_name: "#{settings.cluster_name}-#{node_pool.name}"
      ).run
    end
  end

  private def delete_network
    Hetzner::Network::Delete.new(
      hetzner_client: hetzner_client,
      network_name: settings.cluster_name
    ).run
  end

  private def delete_firewall
    Hetzner::Firewall::Delete.new(
      hetzner_client: hetzner_client,
      firewall_name: settings.cluster_name
    ).run
  end

  private def delete_ssh_key
    Hetzner::SSHKey::Delete.new(
      hetzner_client: hetzner_client,
      ssh_key_name: settings.cluster_name,
      public_ssh_key_path: public_ssh_key_path
    ).run
  end

  private def initialize_masters
    settings.masters_pool.instance_count.times do |i|
      server_deletors << Hetzner::Server::Delete.new(
        hetzner_client: hetzner_client,
        server_name: "#{settings.cluster_name}-#{settings.masters_pool.instance_type}-master#{i + 1}"
      )
    end
  end

  private def initialize_worker_nodes
    no_autoscaling_worker_node_pools = settings.worker_node_pools.reject(&.autoscaling_enabled)

    no_autoscaling_worker_node_pools.each do |node_pool|
      node_pool.instance_count.times do |i|
        server_deletors << Hetzner::Server::Delete.new(
          hetzner_client: hetzner_client,
          server_name: "#{settings.cluster_name}-#{node_pool.instance_type}-pool-#{node_pool.name}-worker#{i + 1}"
        )
      end
    end
  end
end
