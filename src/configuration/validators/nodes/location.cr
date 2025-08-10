require "../../models/node_pool"
require "../../../hetzner/location"

class Configuration::Validators::Nodes::Location
  getter errors : Array(String)
  getter pool : Configuration::Models::MasterNodePool | Configuration::Models::WorkerNodePool
  getter pool_type : Symbol
  getter masters_pool : Configuration::Models::MasterNodePool
  getter all_locations : Array(Hetzner::Location)

  def initialize(@errors, @pool, @pool_type, @masters_pool, @all_locations)
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
    masters_pool? ? validate_masters_pool_locations : validate_worker_pool_location
  end

  private def masters_pool?
    pool_type == :masters
  end

  private def masters_network_zone
    network_zone_by_location(masters_pool.locations.first)
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

    valid_locations = masters_pool.locations.all? { |loc| location_exists?(loc) }
    same_network_zone = masters_pool.locations.map { |loc| network_zone_by_location(loc) }.uniq.size == 1

    return if valid_locations && same_network_zone
    errors << "All must be in valid locations and in the same same network zone when using a private network"
  end

  private def validate_worker_pool_location
    pool_location = pool.as(Configuration::Models::WorkerNodePool).location
    return if location_exists?(pool_location) && network_zone_by_location(pool_location) == masters_network_zone

    errors << "All workers must be in valid locations and in the same same network zone as the masters when using a private network. If the masters are located in Ashburn, then all the worker must be located in Ashburn too. Same thing for Hillsboro and Singapore. If the masters are located in Germany and/or Finland, then also the workers must all be located in either Germany or Finland since these locations belong to the same network zone."
  end

  private def location_exists?(location_name)
    all_locations.any? { |loc| loc.name == location_name }
  end

  private def network_zone_by_location(location)
    ::Configuration::Validators::Nodes::Location.network_zone_by_location(location)
  end
end
