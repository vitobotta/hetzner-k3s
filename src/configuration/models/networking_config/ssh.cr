class Configuration::Models::NetworkingConfig::SSH
  include YAML::Serializable
  include YAML::Serializable::Unmapped

  getter port : Int32 = 22
  getter use_agent : Bool = false
  getter private_key_path : String = "~/.ssh/id_rsa"
  getter public_key_path : String = "~/.ssh/id_rsa.pub"

  def initialize
  end

  def private_key_path
    absolute_path(@private_key_path)
  end

  def public_key_path
    absolute_path(@public_key_path)
  end

  private def absolute_path(path)
    home_dir = ENV["HOME"]? || raise "HOME environment variable not set"
    File.expand_path(path.sub("~/", "#{home_dir}/"))
  end
end
