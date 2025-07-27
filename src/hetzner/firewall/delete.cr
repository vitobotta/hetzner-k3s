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

    log_line "Deleting firewall..."
    delete_firewall(firewall.id)
    log_line "...firewall deleted."

    firewall_name
  end

  private def handle_missing_firewall
    log_line "Firewall does not exist, skipping delete"
    firewall_name
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
