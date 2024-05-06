require "../client"
require "../firewall"
require "../firewalls_list"

class Hetzner::Firewall::Find
  getter hetzner_client : Hetzner::Client
  getter firewall_name : String

  def initialize(@hetzner_client, @firewall_name)
  end

  def run
    firewalls = fetch_firewalls

    firewalls.find { |firewall| firewall.name == firewall_name }
  end

  private def fetch_firewalls
    Retriable.retry(max_attempts: 10, backoff: false, base_interval: 5.seconds) do
      success, response = hetzner_client.get("/firewalls")

      if success
        FirewallsList.from_json(response).firewalls
      else
        STDERR.puts "[#{default_log_prefix}] Failed to fetch firewall: #{response}"
        STDERR.puts "[#{default_log_prefix}] Retrying to fetch firewall in 5 seconds..."
        raise "Failed to fetch firewall"
      end
    end
  end

  private def default_log_prefix
    "Firewall"
  end
end
