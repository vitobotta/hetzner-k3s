require "yaml"
require "./s3"

class Configuration::Datastore
  include YAML::Serializable

  getter mode : String = "etcd"
  getter external_datastore_endpoint : String = ""

  getter s3 : Configuration::S3 = Configuration::S3.new

  def initialize(@mode : String = "etcd", @external_datastore_endpoint : String = "")
  end
end
