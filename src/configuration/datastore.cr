require "yaml"
require "./datastore/etcd"

module Configuration
  module Datastore
    class Config
      include YAML::Serializable

      getter mode : String = "etcd"
      getter external_datastore_endpoint : String = ""

      getter etcd : ::Configuration::Datastore::Etcd = ::Configuration::Datastore::Etcd.new

      def initialize(@mode : String = "etcd", @external_datastore_endpoint : String = "")
      end
    end
  end
end
