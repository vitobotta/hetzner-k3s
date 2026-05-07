class Configuration::Models::NetworkingConfig::SSH
  include YAML::Serializable
  include YAML::Serializable::Unmapped

  getter port : Int32 = 22
  getter use_agent : Bool = false
  getter use_private_ip : Bool = false
  getter private_key_path : String = "~/.ssh/id_rsa"
  getter public_key_path : String = "~/.ssh/id_rsa.pub"
  getter existing_ssh_key_name : String = ""

  def initialize
  end

  def private_key_path
    absolute_path(@private_key_path)
  end

  def public_key_path
    absolute_path(@public_key_path)
  end

  def ssh_key_name(cluster_name : String) : String
    @existing_ssh_key_name.empty? ? cluster_name : @existing_ssh_key_name
  end

  def using_existing_ssh_key? : Bool
    !@existing_ssh_key_name.empty?
  end

  private def absolute_path(path)
    home_dir = ENV["HOME"]? || raise "HOME environment variable not set"
    File.expand_path(path.sub("~/", "#{home_dir}/"))
  end
end
