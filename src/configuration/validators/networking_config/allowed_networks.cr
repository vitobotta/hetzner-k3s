require "crest"
require "ipaddress"

require "../../models/networking_config/allowed_networks"

class Configuration::Validators::NetworkingConfig::AllowedNetworks
  getter errors : Array(String) = [] of String
  getter allowed_networks : Configuration::Models::NetworkingConfig::AllowedNetworks

  def initialize(@errors, @allowed_networks)
  end

  def validate
    validate_networks(errors, allowed_networks.ssh, "SSH")
    validate_networks(errors, allowed_networks.api, "API")
  end

  private def validate_current_ip_must_be_included_in_at_least_one_network(errors, networks, network_type)
    current_ip = nil

    begin
      current_ip = IPAddress.new(Crest.get("https://ipinfo.io/ip").body)
    rescue ex : Crest::RequestFailed
      errors << "Unable to determine your current IP (necessary to validate allowed networks for SSH and API)"
      return
    end

    return if networks.any? { |cidr| current_ip_in_network?(errors, cidr, current_ip, network_type) }
    errors << "Your current IP #{current_ip} must belong to at least one of the #{network_type} allowed networks"
  end

  private def current_ip_in_network?(errors, cidr : String, current_ip : IPAddress, network_type) : Bool
    network = IPAddress.new(cidr).network
    network.includes?(current_ip)
  rescue ex : ArgumentError
    message = ex.message.try(&.includes?("Invalid netmask")) ? "#{network_type} allowed network #{cidr} has an invalid netmask" : "#{network_type} allowed network #{cidr} is not a valid network in CIDR notation"
    errors << message
    false
  end

  private def validate_networks(errors, networks, network_type)
    return errors << "#{network_type} allowed networks are required" if networks.nil? || networks.empty?

    networks.each do |cidr|
      begin
        IPAddress.new(cidr).network?
      rescue ArgumentError
        errors << "#{network_type} allowed network #{cidr} is not a valid network in CIDR notation"
      end
    end
    
    validate_current_ip_must_be_included_in_at_least_one_network(errors, networks, network_type)
  end
end