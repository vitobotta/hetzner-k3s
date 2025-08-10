require "../../models/node_pool"
require "../../../hetzner/location"

class Configuration::Validators::NodePoolConfig::Location
  getter errors : Array(String)
  getter pool : Configuration::Models::MasterNodePool | Configuration::Models::WorkerNodePool
  getter pool_type : Symbol
  getter masters_pool : Configuration::Models::MasterNodePool
  getter all_locations : Array(Hetzner::Location)
  getter private_network_enabled : Bool
  getter datastore_mode : String

  def initialize(@errors, @pool, @pool_type, @masters_pool, @all_locations, @private_network_enabled, @datastore_mode)
  end

  def self.network_zone_by_location(location)
    case location
    when "ash"
      "us-east"
    when "hil"
      "us-west"
    when "sin"
      "ap-southeast"
    else
      "eu-central"
    end
  end

  def validate
    if should_validate_network_zones?
      if pool_type == :masters
        validate_masters_pool_locations
      else
        validate_worker_pool_location
      end
    end
  end

  private def should_validate_network_zones?
    if pool_type == :masters
      private_network_enabled || datastore_mode == "etcd"
    else
      private_network_enabled
    end
  end

  private def validate_masters_pool_locations
    if masters_pool.locations.size != masters_pool.instance_count
      errors << "The number of locations specified for masters must equal the total number of masters"
    else
      validate_masters_locations_and_network_zone
    end
  end

  private def validate_masters_locations_and_network_zone
    return if masters_pool.locations.empty?

    # Check if all locations are valid
    valid_locations = masters_pool.locations.all? { |loc| location_exists?(loc) }

    # Check if all locations are in the same network zone
    network_zones = masters_pool.locations.map { |loc| self.class.network_zone_by_location(loc) }
    same_network_zone = network_zones.uniq.size == 1

    errors << "All masters must be in valid locations and in the same network zone when using a private network or etcd datastore" unless valid_locations && same_network_zone
  end

  private def validate_worker_pool_location
    pool_location = pool.as(Configuration::Models::WorkerNodePool).location
    return if location_exists?(pool_location) && self.class.network_zone_by_location(pool_location) == self.class.network_zone_by_location(masters_pool.locations.first)

    errors << "All workers must be in valid locations and in the same network zone as the masters when using a private network or etcd datastore"
  end

  private def location_exists?(location_name)
    all_locations.any? { |loc| loc.name == location_name }
  end
end
