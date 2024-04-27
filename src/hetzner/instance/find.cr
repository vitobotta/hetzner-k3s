require "../client"
require "../instance"
require "../instances_list"

class Hetzner::Instance::Find
  getter hetzner_client : Hetzner::Client
  getter instance_name : String

  def initialize(@hetzner_client, @instance_name)
  end

  def run
    instances = Retriable.retry(max_attempts: 10, backoff: false, base_interval: 5.seconds) do
      success, response = hetzner_client.get("/servers", { :name => instance_name })

      if success
        InstancesList.from_json(response).servers
      else
        STDERR.puts "[#{default_log_prefix}] Failed to fetch instance #{instance_name}: #{response}"
        STDERR.puts "[#{default_log_prefix}] Retrying to fetch instance #{instance_name} in 5 seconds..."
        raise "Failed to fetch instance"
      end
    end

    instances.find do |instance|
      instance.name == instance_name
    end
  end

  def default_log_prefix
    "Instances"
  end
end
