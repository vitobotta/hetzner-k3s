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

  def initialize(@configuration)
  end

  def run
    Hetzner::LoadBalancer::Delete.new(
      hetzner_client: hetzner_client,
      load_balancer_name: settings.cluster_name
    ).run

    delete_masters

    Hetzner::PlacementGroup::Delete.new(
      hetzner_client: hetzner_client,
      placement_group_name: "#{settings.cluster_name}-masters"
    ).run

    Hetzner::Network::Delete.new(
      hetzner_client: hetzner_client,
      network_name: settings.cluster_name
    ).run

    Hetzner::Firewall::Delete.new(
      hetzner_client: hetzner_client,
      firewall_name: settings.cluster_name
    ).run

    Hetzner::SSHKey::Delete.new(
      hetzner_client: hetzner_client,
      ssh_key_name: settings.cluster_name,
      public_ssh_key_path: public_ssh_key_path
    ).run
  end

  private def delete_masters
    channel = Channel(String).new

    masters_pool = settings.masters_pool

    masters_pool.instance_count.times do |i|
      instance_type = masters_pool.instance_type
      master_name = "#{settings.cluster_name}-#{instance_type}-master#{i + 1}"

      spawn do
        server_name = Hetzner::Server::Delete.new(
          hetzner_client: hetzner_client,
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
