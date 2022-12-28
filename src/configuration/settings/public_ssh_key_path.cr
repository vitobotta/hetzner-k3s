class Configuration::Settings::PublicSSHKeyPath
  getter errors : Array(String)
  getter public_ssh_key_path : String

  def initialize(@errors, @public_ssh_key_path)
  end

  def validate
    if ! File.exists?(public_ssh_key_path)
      errors << "public_ssh_key_path does not exist"
    elsif File.directory?(public_ssh_key_path)
      errors << "public_ssh_key_path is a directory, while we expect a public key file"
    end
  end
end
