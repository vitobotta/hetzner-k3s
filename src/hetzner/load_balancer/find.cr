require "../client"
require "../load_balancer"
require "../load_balancers_list"

class Hetzner::LoadBalancer::Find
  private getter hetzner_client : Hetzner::Client
  private getter load_balancer_name : String

  def initialize(@hetzner_client, @load_balancer_name)
  end

  def run
    fetch_load_balancers.find { |load_balancer| load_balancer.name == load_balancer_name }
  end

  private def fetch_load_balancers
    Retriable.retry(max_attempts: 10, backoff: false, base_interval: 5.seconds) do
      success, response = hetzner_client.get("/load_balancers")

      if success
        LoadBalancersList.from_json(response).load_balancers
      else
        STDERR.puts "[#{default_log_prefix}] Failed to fetch load balancers: #{response}"
        STDERR.puts "[#{default_log_prefix}] Retrying to fetch load balancers in 5 seconds..."
        raise "Failed to fetch load balancers"
      end
    end
  end

  private def default_log_prefix
    "API Load balancer"
  end
end
