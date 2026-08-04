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
    # The target is not removed first: deleting the load balancer removes its targets anyway,
    # and a failing remove_target (e.g. the target is already absent) must not block deletion.
    Retriable.retry(max_attempts: 10, backoff: false, base_interval: 5.seconds, max_elapsed_time: 3.hours) do
      success, response = hetzner_client.delete("/load_balancers", load_balancer_id)

      unless success
        # The load balancer may already be gone, e.g. when the response to a previous delete
        # was lost or it was deleted concurrently.
        next if deleted?(load_balancer_id)

        STDERR.puts "[#{default_log_prefix}] Failed to delete load balancer: #{response}"
        STDERR.puts "[#{default_log_prefix}] Retrying to delete load balancer in 5 seconds..."
        raise "Failed to delete load balancer"
      end
    end
  end

  # Only a 404 for the specific ID counts as deleted: unlike a missing entry in a listing,
  # which can be momentarily stale, it is authoritative and unaffected by renames.
  private def deleted?(load_balancer_id) : Bool
    success, response = hetzner_client.get("/load_balancers/#{load_balancer_id}")
    return false if success

    JSON.parse(response).dig?("error", "code") == "not_found"
  rescue IO::Error | OpenSSL::SSL::Error | JSON::ParseException
    false
  end

  private def handle_missing_load_balancer
    load_balancer_name
  end

  private def default_log_prefix
    "API Load balancer"
  end
end
