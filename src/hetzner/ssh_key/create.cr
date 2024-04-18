require "../client"
require "./find"
require "../../util"

class Hetzner::SSHKey::Create
  include Util

  getter hetzner_client : Hetzner::Client
  getter settings : Configuration::Main
  getter ssh_key_name : String
  getter public_ssh_key_path : String
  getter ssh_key_finder : Hetzner::SSHKey::Find

  def initialize(@hetzner_client, @settings)
    @ssh_key_name = settings.cluster_name
    @public_ssh_key_path = settings.networking.ssh.public_key_path
    @ssh_key_finder = Hetzner::SSHKey::Find.new(hetzner_client, ssh_key_name, public_ssh_key_path)
  end

  def run
    ssh_key = ssh_key_finder.run

    if ssh_key
      log_line "SSH key already exists, skipping create"
    else
      log_line "Creating SSH key..."

      create_ssh_key
      ssh_key = ssh_key_finder.run

      log_line "...SSH key created"
    end

    ssh_key.not_nil!

  rescue ex : Crest::RequestFailed
    STDERR.puts "[#{default_log_prefix}] Failed to create SSH key: #{ex.message}"
    exit 1
  end

  private def create_ssh_key
    ssh_key_config = {
        "name" => ssh_key_name,
        "public_key" => File.read(public_ssh_key_path).chomp
    }

    hetzner_client.post("/ssh_keys", ssh_key_config)
  end

  private def default_log_prefix
    "SSH key"
  end
end
