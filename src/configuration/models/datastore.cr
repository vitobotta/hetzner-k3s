require "yaml"

require "./datastore_config/etcd"

class Configuration::Models::Datastore
  include YAML::Serializable

  getter mode : String = "etcd"
  getter external_datastore_endpoint : String = ""
  getter etcd : ::Configuration::Models::DatastoreConfig::Etcd = ::Configuration::Models::DatastoreConfig::Etcd.new

  def initialize(@mode : String = "etcd", @external_datastore_endpoint : String = "", @etcd : ::Configuration::Models::DatastoreConfig::Etcd = ::Configuration::Models::DatastoreConfig::Etcd.new)
  end
end