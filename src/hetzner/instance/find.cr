require "../client"
require "../instance"
require "../instances_list"
require "../../util"

class Hetzner::Instance::Find
  include Util

  private getter hetzner_client : Hetzner::Client
  private getter instance_name : String
  private getter settings : Configuration::Main

  def initialize(@settings, @hetzner_client, @instance_name)
  end

  def run
    fetch_instances.find { |instance| instance.name == instance_name }
  end

  private def fetch_instances
    Retriable.retry(max_attempts: 10, backoff: false, base_interval: 5.seconds) do
      success, response = hetzner_client.get("/servers", {:name => instance_name})

      if success
        InstancesList.from_json(response).servers
      else
        STDERR.puts "[#{default_log_prefix}] Failed to fetch instance #{instance_name}: #{response}"
        STDERR.puts "[#{default_log_prefix}] Retrying to fetch instance #{instance_name} in 5 seconds..."
        raise "Failed to fetch instance"
      end
    end
  end

  private def default_log_prefix
    "Instances"
  end
end
