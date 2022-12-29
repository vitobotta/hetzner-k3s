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
    ssh_keys = SSHKeysList.from_json(hetzner_client.get("/ssh_keys")).ssh_keys

    private_key = File.read(public_ssh_key_path).split[1]
    fingerprint = Digest::MD5.hexdigest(Base64.decode(private_key)).chars.each_slice(2).map(&.join).join(":")

    key = ssh_keys.find do |ssh_key|
      ssh_key.fingerprint == fingerprint
    end

    key ||= ssh_keys.find do |ssh_key|
      ssh_key.name == ssh_key_name
    end

    key
  end
end
