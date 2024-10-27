require "yaml"
require "./etcd_s3"

class Configuration::Datastore::Backups
  include YAML::Serializable

  getter enabled : Bool = true
  getter retention : Int32?
  getter dir : String?
  getter compress : Bool = false
  getter s3 : Configuration::Datastore::S3 = Configuration::Datastore::S3.new

  def initialize(@enabled : Bool = true, @compress : Bool = false, @s3 : Configuration::Datastore::S3 = Configuration::Datastore::S3.new)
  end
end
