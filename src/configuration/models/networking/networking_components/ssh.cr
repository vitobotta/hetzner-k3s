require "../../../../hetzner/client"
require "../../../../hetzner/ssh_key/find"
require "../../../../util/ssh"

class Configuration::NetworkingComponents::SSH
  include YAML::Serializable
  include YAML::Serializable::Unmapped

  getter port : Int32 = 22
  getter use_agent : Bool = false
  getter private_key_path : String = "~/.ssh/id_rsa"
  getter public_key_path : String = "~/.ssh/id_rsa.pub"

  def initialize
  end

  def validate(errors, hetzner_client = nil, cluster_name = nil)
    validate_path(errors, private_key_path, "private")
    validate_path(errors, public_key_path, "public")
    validate_ssh_key_fingerprint(errors, hetzner_client, cluster_name)
  end

  def private_key_path
    absolute_path(@private_key_path)
  end

  def public_key_path
    absolute_path(@public_key_path)
  end

  private def validate_path(errors, path, key_type)
    return errors << "#{key_type}_key_path does not exist" unless File.exists?(path)
    errors << "#{key_type}_key_path is a directory, while we expect a public key file" if File.directory?(path)
  end

  private def validate_ssh_key_fingerprint(errors, hetzner_client, cluster_name)
    return unless File.exists?(public_key_path)

    existing_ssh_key = find_existing_ssh_key(hetzner_client, cluster_name)
    return unless existing_ssh_key

    config_fingerprint = Util::SSH.calculate_fingerprint(public_key_path)

    if existing_ssh_key.fingerprint != config_fingerprint
      errors << "SSH key mismatch: the key '#{cluster_name}' already exists in Hetzner with a different fingerprint. Please use a different cluster name or update the SSH key in your configuration."
    end
  end

  private def find_existing_ssh_key(hetzner_client, cluster_name)
    ssh_key_finder = Hetzner::SSHKey::Find.new(hetzner_client, cluster_name, public_key_path)
    ssh_key_finder.run
  rescue e
    # If we can't fetch existing SSH keys, we'll skip validation
    # This allows the create command to proceed and handle any API errors
    nil
  end

  private def absolute_path(path)
    home_dir = ENV["HOME"]? || raise "HOME environment variable not set"
    File.expand_path(path.sub("~/", "#{home_dir}/"))
  end
end
