require "yaml"
require "./etcd_backups"

class Configuration::Datastore::Etcd
  include YAML::Serializable

  getter backups : Configuration::Datastore::Backups = Configuration::Datastore::Backups.new

  def initialize(@backups : Configuration::Datastore::Backups = Configuration::Datastore::Backups.new)
  end
end
