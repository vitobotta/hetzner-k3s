require "../../../hetzner/client"
require "../../../hetzner/ssh_key/find"
require "../../../util/ssh"
require "../../models/networking_config/ssh"

class Configuration::Validators::NetworkingConfig::SSH
  getter errors : Array(String)
  getter ssh : Configuration::Models::NetworkingConfig::SSH
  getter hetzner_client : Hetzner::Client?
  getter cluster_name : String?

  def initialize(@errors, @ssh, @hetzner_client = nil, @cluster_name = nil)
  end

  def validate
    validate_path(errors, ssh.private_key_path, "private")
    validate_path(errors, ssh.public_key_path, "public")

    if ssh.using_existing_ssh_key?
      validate_existing_ssh_key(errors, hetzner_client)
    else
      validate_ssh_key_fingerprint(errors, hetzner_client, cluster_name)
    end
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

  private def validate_existing_ssh_key(errors, hetzner_client)
    unless File.exists?(ssh.public_key_path)
      errors << "public_key_path is required to validate the fingerprint of existing_ssh_key_name '#{ssh.existing_ssh_key_name}'"
      return
    end

    begin
      existing_ssh_key = Hetzner::SSHKey::Find.new(hetzner_client.not_nil!, ssh.existing_ssh_key_name, ssh.public_key_path).run
    rescue e
      errors << "Unable to verify existing SSH key '#{ssh.existing_ssh_key_name}': #{e.message}"
      return
    end

    unless existing_ssh_key
      errors << "The SSH key '#{ssh.existing_ssh_key_name}' specified in existing_ssh_key_name does not exist in Hetzner"
      return
    end

    unless existing_ssh_key.name == ssh.existing_ssh_key_name
      errors << "SSH key mismatch: the key '#{ssh.existing_ssh_key_name}' was not found by name in Hetzner. A key with the same fingerprint exists as '#{existing_ssh_key.name}', but existing_ssh_key_name must match the key name exactly."
      return
    end

    config_fingerprint = Util::SSH.calculate_fingerprint(ssh.public_key_path)

    if existing_ssh_key.fingerprint != config_fingerprint
      errors << "SSH key fingerprint mismatch: the existing key '#{ssh.existing_ssh_key_name}' in Hetzner has a different fingerprint than the local public key at '#{ssh.public_key_path}'. Please ensure the public_key_path points to the corresponding public key."
    end
  end

  private def find_existing_ssh_key(hetzner_client, cluster_name)
    return nil unless hetzner_client && cluster_name
    ssh_key_finder = Hetzner::SSHKey::Find.new(hetzner_client, cluster_name, ssh.public_key_path)
    ssh_key_finder.run
  rescue e
    nil
  end
end