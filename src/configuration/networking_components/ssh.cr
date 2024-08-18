class Configuration::NetworkingComponents::SSH
  include YAML::Serializable
  include YAML::Serializable::Unmapped

  getter port : Int32 = 22
  getter use_agent : Bool = false
  getter private_key_path : String = "~/.ssh/id_rsa"
  getter public_key_path : String = "~/.ssh/id_rsa.pub"

  def initialize
  end

  def validate(errors)
    validate_path(errors, private_key_path, "private")
    validate_path(errors, public_key_path, "public")
  end

  def private_key_path
    absolute_path(@private_key_path)
  end

  def public_key_path
    absolute_path(@public_key_path)
  end

  private def validate_path(errors, path, key_type)
    if ! File.exists?(path)
      errors << "#{key_type}_key_path does not exist"
    elsif File.directory?(path)
      errors << "#{key_type}_key_path is a directory, while we expect a public key file"
    end
  end

  private def absolute_path(path)
    home_dir = ENV["HOME"]? || raise "HOME environment variable not set"
    relative_path = path.sub("~/", "#{home_dir}/")
    absolute_path = File.expand_path(relative_path)
  end
end
