require "../hetzner/client"
require "../hetzner/firewall/create"

class FirewallManager
  private getter settings : Configuration::Main
  private getter hetzner_client : Hetzner::Client
  private getter firewall_name : String

  def initialize(@settings, @hetzner_client)
    @firewall_name = settings.cluster_name
  end

  def handle(master_instances)
    return if settings.networking.public_network.use_local_firewall

    firewall_creator = Hetzner::Firewall::Create.new(
      settings,
      hetzner_client,
      firewall_name,
      master_instances
    )

    firewall_creator.run
  end
end
