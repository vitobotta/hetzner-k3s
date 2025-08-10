require "../models/master_node_pool"
require "../models/datastore"
require "../../hetzner/instance_type"
require "../../hetzner/location"
require "./node_pool"

class Configuration::Validators::MastersPool
  getter errors : Array(String) = [] of String
  getter masters_pool : Configuration::Models::MasterNodePool
  getter instance_types : Array(Hetzner::InstanceType)
  getter all_locations : Array(Hetzner::Location)
  getter datastore : Configuration::Models::Datastore
  getter private_network_enabled : Bool

  def initialize(
    @errors,
    @masters_pool,
    @instance_types,
    @all_locations,
    @datastore,
    @private_network_enabled
  )
  end

  def validate
    Configuration::Validators::NodePool.new(
      errors: errors,
      pool: masters_pool,
      pool_type: :masters,
      masters_pool: masters_pool,
      instance_types: instance_types,
      all_locations: all_locations,
      datastore: datastore,
      private_network_enabled: private_network_enabled
    ).validate
  end
end