require "yaml"

class Configuration::Models::ExternalNode
  include YAML::Serializable

  property host : String
  property ssh_user : String
  property ssh_port : Int32 = 22
  property ssh_private_key_path : String
  property manage_hostname : Bool = true
  property index : Int32

  def ssh_private_key_path
    absolute_path(@ssh_private_key_path)
  end

  private def absolute_path(path)
    home_dir = ENV["HOME"]? || raise "HOME environment variable not set"
    File.expand_path(path.sub("~/", "#{home_dir}/"))
  end
end
