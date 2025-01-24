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
    all_ssh_keys = [] of SSHKey
    page = 1
    per_page = 25

    loop do
      success, response = hetzner_client.get("/ssh_keys", { :page => page, :per_page => per_page })

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

  private def calculate_fingerprint(public_ssh_key_path)
    private_key = File.read(public_ssh_key_path).split[1]
    Digest::MD5.hexdigest(Base64.decode(private_key)).chars.each_slice(2).map(&.join).join(":")
  end

  private def default_log_prefix
    "SSH key"
  end
end
