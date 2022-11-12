require "./client"
require "./ssh_keys_list"

class Hetzner::SSHKey
  include JSON::Serializable

  property id : Int32?
  property name : String?
  property fingerprint : String?

  def self.create(hetzner_client, ssh_key_name, public_ssh_key_path)
    puts

    if ssh_key = find(hetzner_client, ssh_key_name, public_ssh_key_path)
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

  private def self.find(hetzner_client, ssh_key_name, public_ssh_key_path)
    ssh_keys = SSHKeysList.from_json(hetzner_client.not_nil!.get("/ssh_keys")).ssh_keys

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
