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
    if ssh_key = ssh_key_finder.run
      if ssh_key.name == ssh_key_name # same name as the cluster
        print "Deleting SSH key..."

        hetzner_client.delete("/ssh_keys", ssh_key.id)

        puts "done."
      else
        puts "The SSH key existed before creating the cluster, so I won't delete it."
      end
    else
      puts "SSH key does not exist, skipping."
    end

    ssh_key_name

  rescue ex : Crest::RequestFailed
    STDERR.puts "Failed to delete ssh key: #{ex.message}"
    STDERR.puts ex.response

    exit 1
  end
end
