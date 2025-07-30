require "../client"
require "./find"
require "../../util"

class Hetzner::Firewall::Delete
  include Util

  getter hetzner_client : Hetzner::Client
  getter firewall_name : String
  getter firewall_finder : Hetzner::Firewall::Find

  def initialize(@hetzner_client, @firewall_name)
    @firewall_finder = Hetzner::Firewall::Find.new(@hetzner_client, @firewall_name)
  end

  def run
    firewall = firewall_finder.run

    return handle_missing_firewall unless firewall

    log_line "Removing firewall label selectors from firewall..."
    remove_firewall_from_servers(firewall.id)
    log_line "...firewall label selectors removed."

    log_line "Waiting for firewall actions to complete..."
    wait_for_firewall_actions(firewall.id)
    log_line "...all firewall actions completed."

    log_line "Deleting firewall..."
    delete_firewall(firewall.id)
    log_line "...firewall deleted."

    firewall_name
  end

  private def handle_missing_firewall
    log_line "Firewall does not exist, skipping delete"
    firewall_name
  end

  private def remove_firewall_from_servers(firewall_id)
    Retriable.retry(max_attempts: 10, backoff: false, base_interval: 5.seconds) do
      path = "/firewalls/#{firewall_id}/actions/remove_from_resources"
      request_body = {
        :remove_from => [
          {
            :label_selector => {
              :selector => "cluster=#{firewall_name}",
            },
            :type => "label_selector"
          }
        ]
      }

      success, response = hetzner_client.post(path, request_body)

      unless success
        STDERR.puts "[#{default_log_prefix}] Failed to update firewall: #{response}"
        STDERR.puts "[#{default_log_prefix}] Retrying to update firewall in 5 seconds..."
        raise "Failed to update firewall"
      end
    end
  end

  private def wait_for_firewall_actions(firewall_id)
    Retriable.retry(max_attempts: 30, backoff: false, base_interval: 10.seconds) do
      success, response = hetzner_client.get("/firewalls/#{firewall_id}/actions")

      unless success
        STDERR.puts "[#{default_log_prefix}] Failed to get firewall actions: #{response}"
        STDERR.puts "[#{default_log_prefix}] Retrying to get firewall actions in 10 seconds..."
        raise "Failed to get firewall actions"
      end

      actions = JSON.parse(response)["actions"].as_a

      pending_actions = actions.select do |action|
        action["status"].as_s == "running"
      end

      if pending_actions.size > 0
        log_line "Waiting for #{pending_actions.size} pending firewall actions to complete..."
        raise "Firewall actions still pending"
      end
    end
  end

  private def delete_firewall(firewall_id)
    Retriable.retry(max_attempts: 10, backoff: false, base_interval: 5.seconds) do
      success, response = hetzner_client.delete("/firewalls", firewall_id)

      unless success
        STDERR.puts "[#{default_log_prefix}] Failed to delete firewall: #{response}"
        STDERR.puts "[#{default_log_prefix}] Retrying to delete firewall in 5 seconds..."
        raise "Failed to delete firewall"
      end
    end
  end

  private def default_log_prefix
    "Firewall"
  end
end
