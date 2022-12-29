class Configuration::Settings::PrivateSSHKeyPath
  getter errors : Array(String)
  getter private_ssh_key_path : String

  def initialize(@errors, @private_ssh_key_path)
  end

  def validate
    if ! File.exists?(private_ssh_key_path)
      errors << "private_ssh_key_path does not exist"
    elsif File.directory?(private_ssh_key_path)
      errors << "private_ssh_key_path is a directory, while we expect a public key file"
    end
  end
end
