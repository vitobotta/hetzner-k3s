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

    return ssh_key if ssh_key

    log_line "Creating SSH key..."
    create_ssh_key
    log_line "...SSH key created"
    ssh_key_finder.run.not_nil!
  end

  private def create_ssh_key
    ssh_key_config = {
      :name => ssh_key_name,
      :public_key => File.read(public_ssh_key_path).chomp
    }

    Retriable.retry(max_attempts: 10, backoff: false, base_interval: 5.seconds) do
      success, response = hetzner_client.post("/ssh_keys", ssh_key_config)

      unless success
        STDERR.puts "[#{default_log_prefix}] Failed to create SSH key: #{response}"
        STDERR.puts "[#{default_log_prefix}] Retrying to create SSH key in 5 seconds"
        raise "Failed to create SSH key"
      end
    end
  end

  private def default_log_prefix
    "SSH key"
  end
end
