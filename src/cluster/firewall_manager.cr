require "../hetzner/client"
require "../util"
require "../hetzner/firewall/create"
require "../hetzner/firewall/delete"

class FirewallManager
  include Util

  private getter settings : Configuration::Main
  private getter hetzner_client : Hetzner::Client
  private getter firewall_name : String

  def initialize(@settings, @hetzner_client)
    @firewall_name = settings.cluster_name
  end

  def handle(master_instances)
    return remove_hetzner_firewall unless settings.networking.public_network.use_hetzner_firewall
    return if settings.networking.public_network.use_local_firewall

    firewall_creator(master_instances).run
  end

  # Deleting instead of only skipping the create keeps a firewall from an earlier run from staying
  # attached, which is what the quota argument for the setting is about.
  private def remove_hetzner_firewall
    log_line "Removing the Hetzner Cloud firewall...", log_prefix: default_log_prefix

    firewall_deleter.run

    log_line "...Hetzner Cloud firewall removed", log_prefix: default_log_prefix
  end

  def firewall_creator(master_instances)
    Hetzner::Firewall::Create.new(
      settings,
      hetzner_client,
      firewall_name,
      master_instances
    )
  end

  def firewall_deleter
    Hetzner::Firewall::Delete.new(
      hetzner_client: hetzner_client,
      firewall_name: firewall_name
    )
  end

  def default_log_prefix
    "Firewall"
  end
end
