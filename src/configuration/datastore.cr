require "yaml"

class Configuration::Datastore
  include YAML::Serializable

  getter mode : String = "etcd"
  getter external_datastore_endpoint : String = ""

  def initialize(@mode : String = "etcd", @external_datastore_endpoint : String = "")
  end
end
