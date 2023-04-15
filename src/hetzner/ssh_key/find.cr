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
    SSHKeysList.from_json(hetzner_client.get("/ssh_keys")).ssh_keys
  rescue ex : Crest::RequestFailed
    STDERR.puts "Failed to fetch ssh keys: #{ex.message}"
    STDERR.puts ex.response
    exit 1
  end

  private def calculate_fingerprint(public_ssh_key_path)
    private_key = File.read(public_ssh_key_path).split[1]
    Digest::MD5.hexdigest(Base64.decode(private_key)).chars.each_slice(2).map(&.join).join(":")
  end
end
