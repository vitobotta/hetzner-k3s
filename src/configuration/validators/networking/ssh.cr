require "../../../hetzner/client"
require "../../../hetzner/ssh_key/find"
require "../../../util/ssh"
require "../../models/networking_config/ssh"

class Configuration::Validators::Networking::SSH
  getter errors : Array(String)
  getter ssh : Configuration::Models::NetworkingConfig::SSH
  getter hetzner_client : Hetzner::Client?
  getter cluster_name : String?

  def initialize(@errors, @ssh, @hetzner_client = nil, @cluster_name = nil)
  end

  def validate
    validate_path(errors, ssh.private_key_path, "private")
    validate_path(errors, ssh.public_key_path, "public")
    validate_ssh_key_fingerprint(errors, hetzner_client, cluster_name)
  end

  private def validate_path(errors, path, key_type)
    return errors << "#{key_type}_key_path does not exist" unless File.exists?(path)
    errors << "#{key_type}_key_path is a directory, while we expect a public key file" if File.directory?(path)
  end

  private def validate_ssh_key_fingerprint(errors, hetzner_client, cluster_name)
    return unless File.exists?(ssh.public_key_path)

    existing_ssh_key = find_existing_ssh_key(hetzner_client, cluster_name)
    return unless existing_ssh_key

    config_fingerprint = Util::SSH.calculate_fingerprint(ssh.public_key_path)

    if existing_ssh_key.fingerprint != config_fingerprint
      errors << "SSH key mismatch: the key '#{cluster_name}' already exists in Hetzner with a different fingerprint. Please use a different cluster name or update the SSH key in your configuration."
    end
  end

  private def find_existing_ssh_key(hetzner_client, cluster_name)
    return nil unless hetzner_client && cluster_name
    ssh_key_finder = Hetzner::SSHKey::Find.new(hetzner_client, cluster_name, ssh.public_key_path)
    ssh_key_finder.run
  rescue e
    # If we can't fetch existing SSH keys, we'll skip validation
    # This allows the create command to proceed and handle any API errors
    nil
  end
end