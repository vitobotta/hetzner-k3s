require "./client"
require "./ssh_keys_list"

class Hetzner::SSHKey
  include JSON::Serializable

  property id : Int32?
  property name : String?

  def self.create(hetzner_client, ssh_key_name, public_ssh_key_path)
    puts

    if ssh_key = find(hetzner_client, ssh_key_name)
      puts "SSH key already exists, skipping.\n"
      return ssh_key
    end

    puts "Creating SSH key..."

    begin
      ssh_key_config = {
        "name" => ssh_key_name,
        "public_key" => File.read(public_ssh_key_path).chomp
      }

      ssh_key = hetzner_client.not_nil!.post("/ssh_keys", ssh_key_config)

      puts "...done.\n"

      ssh_key
    rescue ex : Crest::RequestFailed
      STDERR.puts "Failed to create SSH key: #{ex.message}"
      STDERR.puts ex.response

      exit 1
    end
  end

  private def self.find(hetzner_client, ssh_key_name)
    ssh_keys = SSHKeysList.from_json(hetzner_client.not_nil!.get("/ssh_keys")).ssh_keys

    ssh_keys.find do |ssh_Key|
      ssh_Key.name == ssh_key_name
    end
  end
end
