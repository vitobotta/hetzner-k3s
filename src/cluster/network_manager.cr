require "../hetzner/network/create"
require "../hetzner/network/find"

class Cluster::NetworkManager
  private getter settings : Configuration::Main
  private getter hetzner_client : Hetzner::Client

  def initialize(@settings, @hetzner_client)
  end

  def find_or_create
    find_existing(settings.networking.private_network.existing_network_name) || create_new
  end

  def create_new
    return unless settings.networking.private_network.enabled

    Hetzner::Network::Create.new(
      settings: settings,
      hetzner_client: hetzner_client,
      network_name: settings.cluster_name,
      network_zone: ::Configuration::Validators::NodePoolConfig::Location.network_zone_by_location(default_masters_Location)
    ).run
  end

  def find_existing(existing_network_name)
    return nil if existing_network_name.empty?
    Hetzner::Network::Find.new(hetzner_client, existing_network_name).run
  end

  private def default_masters_Location
    settings.masters_pool.locations.first
  end
end
