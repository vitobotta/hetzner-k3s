require "../hetzner/load_balancer/create"
require "../hetzner/load_balancer/delete"

class Cluster::LoadBalancerManager
  private getter settings : Configuration::Main
  private getter hetzner_client : Hetzner::Client

  def initialize(@settings, @hetzner_client)
  end

  def create(location, network_id)
    load_balancer = Hetzner::LoadBalancer::Create.new(
      settings: settings,
      hetzner_client: hetzner_client,
      location: location,
      network_id: network_id
    ).run

    sleep 5.seconds
    load_balancer
  end

  def delete(print_log = false)
    Hetzner::LoadBalancer::Delete.new(
      hetzner_client: hetzner_client,
      cluster_name: settings.cluster_name,
      print_log: print_log
    ).run
  end

  def handle(master_count, network)
    if settings.create_load_balancer_for_the_kubernetes_api && master_count > 1
      create(default_masters_location, network.try(&.id))
    else
      delete
      nil
    end
  end

  private def default_masters_location
    settings.masters_pool.locations.first
  end
end
