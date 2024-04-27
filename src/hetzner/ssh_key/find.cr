require "../client"
require "../ssh_key"
require "../ssh_keys_list"

class Hetzner::SSHKey::Find
  getter hetzner_client : Hetzner::Client
  getter ssh_key_name : String
  getter public_ssh_key_path : String

  def initialize(@hetzner_client, @ssh_key_name, @public_ssh_key_path)
  end

  def run
    ssh_keys = fetch_ssh_keys
    fingerprint = calculate_fingerprint(public_ssh_key_path)

    key = ssh_keys.find { |ssh_key| ssh_key.fingerprint == fingerprint }
    key ||= ssh_keys.find { |ssh_key| ssh_key.name == ssh_key_name }
    key
  end

  private def fetch_ssh_keys
    Retriable.retry(max_attempts: 10, backoff: false, base_interval: 5.seconds) do
      success, response = hetzner_client.get("/ssh_keys")

      if success
        SSHKeysList.from_json(response).ssh_keys
      else
        STDERR.puts "[#{default_log_prefix}] Failed to fetch ssh keys: #{response}"
        STDERR.puts "[#{default_log_prefix}] Retrying to fetch ssh keys in 5 seconds..."
        raise "Failed to fetch ssh keys"
      end
    end
  end

  private def calculate_fingerprint(public_ssh_key_path)
    private_key = File.read(public_ssh_key_path).split[1]
    Digest::MD5.hexdigest(Base64.decode(private_key)).chars.each_slice(2).map(&.join).join(":")
  end

  private def default_log_prefix
    "SSH key"
  end
end
