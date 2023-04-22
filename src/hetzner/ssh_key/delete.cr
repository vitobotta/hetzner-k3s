require "../client"
require "../ssh_key"
require "../ssh_keys_list"
require "./find"

class Hetzner::SSHKey::Delete
  getter hetzner_client : Hetzner::Client
  getter ssh_key_name : String
  getter ssh_key_finder : Hetzner::SSHKey::Find

  def initialize(@hetzner_client, @ssh_key_name, public_ssh_key_path)
    @ssh_key_finder = Hetzner::SSHKey::Find.new(hetzner_client, ssh_key_name, public_ssh_key_path)
  end

  def run
    ssh_key = ssh_key_finder.run

    return handle_no_ssh_key if ssh_key.nil?
    return handle_existing_ssh_key(ssh_key) if ssh_key.name == ssh_key_name

    puts "The SSH key existed before creating the cluster, so I won't delete it."
    ssh_key_name
  rescue ex : Crest::RequestFailed
    STDERR.puts "Failed to delete ssh key: #{ex.message}"
    STDERR.puts ex.response
    exit 1
  end

  private def handle_no_ssh_key
    puts "SSH key does not exist, skipping."
    ssh_key_name
  end

  private def handle_existing_ssh_key(ssh_key)
    print "Deleting SSH key..."
    hetzner_client.delete("/ssh_keys", ssh_key.id)
    puts "done."
    ssh_key_name
  end
end
