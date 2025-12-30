require "../client"
require "../ssh_key"
require "../ssh_keys_list"
require "../../util/ssh"

class Hetzner::SSHKey::Find
  private getter hetzner_client : Hetzner::Client
  private getter ssh_key_name : String
  private getter public_ssh_key_path : String

  def initialize(@hetzner_client, @ssh_key_name, @public_ssh_key_path)
  end

  def run
    ssh_keys = fetch_ssh_keys
    fingerprint = Util::SSH.calculate_fingerprint(public_ssh_key_path)

    ssh_keys.find { |ssh_key| ssh_key.fingerprint == fingerprint } ||
      ssh_keys.find { |ssh_key| ssh_key.name == ssh_key_name }
  end

  private def fetch_ssh_keys
    all_ssh_keys = [] of SSHKey
    page = 1
    per_page = 25

    Retriable.retry(max_attempts: 10, backoff: false, base_interval: 5.seconds) do
      loop do
        success, response = hetzner_client.get("/ssh_keys", {:page => page.to_s, :per_page => per_page.to_s})

        if success
          ssh_keys = SSHKeysList.from_json(response).ssh_keys
          all_ssh_keys.concat(ssh_keys)
          break if ssh_keys.size < per_page
        else
          STDERR.puts "[#{default_log_prefix}] Failed to fetch ssh keys: #{response}"
          STDERR.puts "[#{default_log_prefix}] Retrying to fetch ssh keys in 5 seconds..."
          raise "Failed to fetch ssh keys"
        end

        page += 1
      end

      all_ssh_keys
    end
  end

  private def default_log_prefix
    "SSH key"
  end
end
