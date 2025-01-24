require "../../node_pool"
require "../../../hetzner/location"

class Configuration::Settings::NodePool::Location
  getter errors : Array(String)
  getter pool : Configuration::NodePool
  getter pool_type : Symbol
  getter masters_location : String?
  getter locations : Array(Hetzner::Location)

  def initialize(@errors, @pool, @pool_type, @masters_location, @locations)
  end

  def validate
    location = pool.location

    if valid_location?(location)
      validate_network_zone(location) if pool_type == :workers && masters_location
    else
      errors << "#{pool_type} pool has an invalid location"
    end
  end

  private def valid_location?(location)
    locations.any? { |loc| loc.name == location }
  end

  private def validate_network_zone(location)
    in_network_zone = if masters_location == "ash"
      location == "ash"
    elsif masters_location == "hil"
      location == "hil"
    elsif masters_location == "sin"
      location == "sin"
    else
      !%w(ash hil sin).includes?(location)
    end

    unless in_network_zone
      errors << "#{pool_type} pool must be in the same network zone as the masters when using a private network. If the masters are located in Ashburn, then all the node pools must be located in Ashburn too, otherwise none of the node pools should be located in Ashburn. Same thing for Hillsboro and Singapore. If the masters are located in Germany or Finland, then also the worker node pools must be located in either Germany or Finland since these locations belong to the same network zone."
    end
  end
end
