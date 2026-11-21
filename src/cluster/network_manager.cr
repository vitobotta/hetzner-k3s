require "../hetzner/network/create"
require "../hetzner/network/find"

class Cluster::NetworkManager
  private getter settings : Configuration::Main
  private getter hetzner_client : Hetzner::Client

  def initialize(@settings, @hetzner_client)
  end

  # A network is looked up by name, so one left behind by an earlier attempt in another region
  # is picked up silently and Hetzner then rejects every server in the new location with an
  # "unsupported location for server type" error. Both the network this tool creates and a user
  # supplied one are checked, since the second is the likelier to be in the wrong zone.
  def find_or_create
    network = find_existing(settings.networking.private_network.existing_network_name) || create_new
    abort_on_zone_mismatch(network)
    network
  end

  def create_new
    return unless settings.networking.private_network.enabled

    Hetzner::Network::Create.new(
      settings: settings,
      hetzner_client: hetzner_client,
      network_name: settings.cluster_name,
      network_zone: required_zone
    ).run
  end

  def find_existing(existing_network_name)
    return nil if existing_network_name.empty?
    Hetzner::Network::Find.new(hetzner_client, existing_network_name).run
  end

  # An empty subnet list and a list that spans zones both land here: a network without the zone
  # this cluster needs cannot host its servers, whatever the reason.
  def zone_mismatch?(network : Hetzner::Network) : Bool
    !network.network_zones.includes?(required_zone)
  end

  def required_zone : String
    ::Configuration::Validators::NodePoolConfig::Location.network_zone_by_location(default_masters_location)
  end

  private def abort_on_zone_mismatch(network : Hetzner::Network?) : Nil
    return unless network
    return unless zone_mismatch?(network)

    zones = network.network_zones
    found = zones.empty? ? "has no subnet" : "has subnets only in #{zones.join(", ")}"

    STDERR.puts "[Private Network] ERROR: The network '#{network.name}' already exists but #{found}, and this cluster needs a subnet in '#{required_zone}' for its location."
    STDERR.puts "[Private Network] This typically happens when a previous cluster creation attempt left a stale network in a different region."
    STDERR.puts "[Private Network] To fix: delete the stale network '#{network.name}' via `hcloud network delete #{network.name}` and retry."
    exit 1
  end

  private def default_masters_location
    settings.masters_pool.locations.first
  end
end
