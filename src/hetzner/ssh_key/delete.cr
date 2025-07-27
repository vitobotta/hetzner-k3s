require "../client"
require "../ssh_key"
require "../ssh_keys_list"
require "./find"
require "../../util"

class Hetzner::SSHKey::Delete
  include Util

  getter hetzner_client : Hetzner::Client
  getter ssh_key_name : String
  getter ssh_key_finder : Hetzner::SSHKey::Find

  def initialize(@hetzner_client, @ssh_key_name, public_ssh_key_path)
    @ssh_key_finder = Hetzner::SSHKey::Find.new(hetzner_client, ssh_key_name, public_ssh_key_path)
  end

  def run
    ssh_key = ssh_key_finder.run

    return handle_no_ssh_key unless ssh_key
    return handle_existing_ssh_key(ssh_key) if ssh_key.name == ssh_key_name

    log_line "An SSH key with the expected fingerprint existed before creating the cluster, so I won't delete it"
    ssh_key_name
  end

  private def handle_no_ssh_key
    log_line "SSH key does not exist, skipping delete"
    ssh_key_name
  end

  private def handle_existing_ssh_key(ssh_key)
    log_line "Deleting SSH key..."

    Retriable.retry(max_attempts: 10, backoff: false, base_interval: 5.seconds) do
      success, response = hetzner_client.delete("/ssh_keys", ssh_key.id)

      if success
        log_line "...SSH key deleted"
      else
        STDERR.puts "[#{default_log_prefix}] Failed to delete ssh key: #{response}"
        STDERR.puts "[#{default_log_prefix}] Retrying to delete ssh key in 5 seconds..."
        raise "Failed to delete ssh key"
      end
    end

    ssh_key_name
  end

  private def default_log_prefix
    "SSH key"
  end
end
