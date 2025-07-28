require "../client"
require "../instance"
require "../instances_list"
require "./find"
require "../../util"

class Hetzner::Instance::Delete
  include Util

  getter hetzner_client : Hetzner::Client
  getter instance_name : String
  getter instance_finder : Hetzner::Instance::Find

  private getter settings : Configuration::Main
  private getter ssh : Configuration::NetworkingComponents::SSH
  private getter ssh_client : Util::SSH do
    Util::SSH.new(ssh.private_key_path, ssh.public_key_path)
  end

  def initialize(@settings, @hetzner_client, @instance_name)
    @ssh = settings.networking.ssh
    @instance_finder = Hetzner::Instance::Find.new(@settings, @hetzner_client, @instance_name)
  end

  def run
    instance = instance_finder.run

    return handle_missing_instance unless instance

    log_line "Deleting instance #{instance_name}..."
    delete_instance(instance.id)
    log_line "...instance #{instance_name} deleted"

    instance_name
  end

  private def handle_missing_instance
    log_line "Instance #{instance_name} does not exist, skipping delete"
    instance_name
  end

  private def delete_instance(instance_id)
    Retriable.retry(max_attempts: 10, backoff: false, base_interval: 5.seconds) do
      success, response = hetzner_client.delete("/servers", instance_id)

      unless success
        STDERR.puts "[#{default_log_prefix}] Failed to delete instance #{instance_name}: #{response}"
        STDERR.puts "[#{default_log_prefix}] Retrying to delete instance #{instance_name} in 5 seconds..."
        raise "Failed to delete instance"
      end
    end
  end

  private def default_log_prefix
    "Instance #{instance_name}"
  end
end
