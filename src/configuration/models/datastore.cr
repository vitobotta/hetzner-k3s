require "yaml"

require "./datastore_config/etcd"

class Configuration::Datastore
  include YAML::Serializable

  getter mode : String = "etcd"
  getter external_datastore_endpoint : String = ""
  getter etcd : ::Configuration::DatastoreTypes::Etcd = ::Configuration::DatastoreTypes::Etcd.new

  def initialize(@mode : String = "etcd", @external_datastore_endpoint : String = "", @etcd : ::Configuration::DatastoreTypes::Etcd = ::Configuration::DatastoreTypes::Etcd.new)
  end
end