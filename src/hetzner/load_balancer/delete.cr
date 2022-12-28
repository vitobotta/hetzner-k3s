require "../client"
require "./find"

class Hetzner::LoadBalancer::Delete
  getter hetzner_client : Hetzner::Client
  getter load_balancer_name : String
  getter load_balancer_finder : Hetzner::LoadBalancer::Find

  def initialize(@hetzner_client, @load_balancer_name)
    @load_balancer_finder = Hetzner::LoadBalancer::Find.new(@hetzner_client, @load_balancer_name)
  end

  def run
    if load_balancer = load_balancer_finder.run
      puts "Deleting load balancer for API server...".colorize(:green)

      hetzner_client.post("/load_balancers/#{load_balancer.id}/actions/remove_target", remove_targets_config)
      hetzner_client.delete("/load_balancers", load_balancer.id)

      puts "...load balancer deleted.\n".colorize(:green)
    else
      puts "Load balancer for API server does not exist, skipping.\n".colorize(:green)
    end

    load_balancer_name

  rescue ex : Crest::RequestFailed
    STDERR.puts "Failed to delete load balancer: #{ex.message}".colorize(:red)
    STDERR.puts ex.response

    exit 1
  end

  private def remove_targets_config
    {
      label_selector: {
        selector: "cluster=#{load_balancer_name},role=master"
      },
      type: "label_selector"
    }
  end
end
