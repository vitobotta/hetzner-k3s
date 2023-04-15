require "../client"
require "./find"

class Hetzner::SSHKey::Create
  getter hetzner_client : Hetzner::Client
  getter ssh_key_name : String
  getter public_ssh_key_path : String
  getter ssh_key_finder : Hetzner::SSHKey::Find

  def initialize(@hetzner_client, @ssh_key_name, @public_ssh_key_path)
    @ssh_key_finder = Hetzner::SSHKey::Find.new(hetzner_client, ssh_key_name, public_ssh_key_path)
  end

  def run
    ssh_key = ssh_key_finder.run

    if ssh_key
      puts "SSH key already exists, skipping."
    else
      print "Creating SSH key..."

      create_ssh_key
      ssh_key = ssh_key_finder.run

      puts "done."
    end

    ssh_key.not_nil!

  rescue ex : Crest::RequestFailed
    STDERR.puts "Failed to create SSH key: #{ex.message}"
    STDERR.puts ex.response

    exit 1
  end

  private def create_ssh_key
    ssh_key_config = {
        "name" => ssh_key_name,
        "public_key" => File.read(public_ssh_key_path).chomp
    }

    hetzner_client.post("/ssh_keys", ssh_key_config)
  end
end
