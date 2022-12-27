require "../configuration/main"
require "../hetzner/placement_group/delete"
require "../hetzner/ssh_key/delete"
require "../hetzner/firewall/delete"
require "../hetzner/network/delete"
require "../hetzner/server/delete"

class Cluster::Delete
  private getter configuration : Configuration::Main

  def initialize(@configuration)
  end

  def run
    delete_masters

    Hetzner::PlacementGroup::Delete.new(
      hetzner_client = configuration.hetzner_client,
      placement_group_name = "#{configuration.cluster_name}-masters"
    ).run

    Hetzner::Network::Delete.new(
      hetzner_client: configuration.hetzner_client,
      network_name: configuration.cluster_name
    ).run

    Hetzner::Firewall::Delete.new(
      hetzner_client: configuration.hetzner_client,
      firewall_name: configuration.cluster_name
    ).run

    Hetzner::SSHKey::Delete.new(
      hetzner_client: configuration.hetzner_client,
      ssh_key_name: configuration.cluster_name,
      public_ssh_key_path: configuration.public_ssh_key_path
    ).run
  end

  private def delete_masters
    channel = Channel(String).new

    masters_pool = configuration.masters_pool

    masters_pool.instance_count.times do |i|
      instance_type = masters_pool.instance_type
      master_name = "#{configuration.cluster_name}-#{instance_type}-master#{i + 1}"

      spawn do
        server_name = Hetzner::Server::Delete.new(
          hetzner_client: configuration.hetzner_client,
          server_name: master_name
        ).run

        channel.send(server_name)
      end
    end

    masters_pool.instance_count.times do
      channel.receive
    end
  end
end
