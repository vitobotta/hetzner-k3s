require "../client"
require "./find"
require "../../util"

class Hetzner::LoadBalancer::Delete
  include Util

  private getter hetzner_client : Hetzner::Client
  private getter cluster_name : String
  private getter load_balancer_name : String do
    "#{cluster_name}-api"
  end
  private getter load_balancer_finder : Hetzner::LoadBalancer::Find
  private getter print_log : Bool = true

  def initialize(@hetzner_client, @cluster_name, @print_log)
    @load_balancer_finder = Hetzner::LoadBalancer::Find.new(@hetzner_client, load_balancer_name)
  end

  def run
    load_balancer = load_balancer_finder.run

    return handle_missing_load_balancer unless load_balancer

    log_line "Deleting load balancer for API server..." if print_log
    delete_load_balancer(load_balancer.id)
    log_line "...load balancer for API server deleted" if print_log

    load_balancer_name
  end

  private def delete_load_balancer(load_balancer_id)
    Retriable.retry(max_attempts: 10, backoff: false, base_interval: 5.seconds) do
      success, response = hetzner_client.post("/load_balancers/#{load_balancer_id}/actions/remove_target", remove_targets_config)

      unless success
        STDERR.puts "[#{default_log_prefix}] Failed to delete load balancer: #{response}"
        STDERR.puts "[#{default_log_prefix}] Retrying to delete load balancer in 5 seconds..."
        raise "Failed to delete load balancer"
      end

      success, response = hetzner_client.delete("/load_balancers", load_balancer_id)

      unless success
        STDERR.puts "[#{default_log_prefix}] Failed to delete load balancer: #{response}"
        STDERR.puts "[#{default_log_prefix}] Retrying to delete load balancer in 5 seconds..."
        raise "Failed to delete load balancer"
      end
    end
  end

  private def remove_targets_config
    {
      :label_selector => {
        :selector => "cluster=#{cluster_name},role=master",
      },
      :type => "label_selector",
    }
  end

  private def handle_missing_load_balancer
    load_balancer_name
  end

  private def default_log_prefix
    "API Load balancer"
  end
end
