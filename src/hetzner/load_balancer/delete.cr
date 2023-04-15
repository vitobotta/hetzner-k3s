require "../client"
require "./find"

class Hetzner::LoadBalancer::Delete
  getter hetzner_client : Hetzner::Client
  getter cluster_name : String
  getter load_balancer_name : String do
    "#{cluster_name}-api"
  end
  getter load_balancer_finder : Hetzner::LoadBalancer::Find

  def initialize(@hetzner_client, @cluster_name)
    @load_balancer_finder = Hetzner::LoadBalancer::Find.new(@hetzner_client, load_balancer_name)
  end

  def run
    load_balancer = load_balancer_finder.run

    if load_balancer
      print "Deleting load balancer for API server..."
      delete_load_balancer(load_balancer.id)
      puts "done."
    else
      puts "Load balancer for API server does not exist, skipping."
    end

    load_balancer_name
  rescue ex : Crest::RequestFailed
    STDERR.puts "Failed to delete load balancer: #{ex.message}"
    STDERR.puts ex.response
    exit 1
  end

  private def delete_load_balancer(load_balancer_id)
    hetzner_client.post("/load_balancers/#{load_balancer_id}/actions/remove_target", remove_targets_config)
    hetzner_client.delete("/load_balancers", load_balancer_id)
  end

  private def remove_targets_config
    {
      label_selector: {
        selector: "cluster=#{cluster_name},role=master"
      },
      type: "label_selector"
    }
  end
end
