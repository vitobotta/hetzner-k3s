require "../client"
require "../instance"
require "../instances_list"

class Hetzner::Instance::Find
  getter hetzner_client : Hetzner::Client
  getter instance_name : String

  def initialize(@hetzner_client, @instance_name)
  end

  def run
    instances = InstancesList.from_json(hetzner_client.get("/servers",{:name => instance_name})).servers
    instances.find do |instance|
      instance.name == instance_name
    end
  rescue ex : Crest::RequestFailed
    STDERR.puts "[#{default_log_prefix}] Failed to fetch instances: #{ex.message}"
    exit 1
  end

  def default_log_prefix
    "Instances"
  end
end
