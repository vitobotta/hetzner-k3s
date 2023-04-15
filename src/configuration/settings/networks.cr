require "ipaddress"
require "crest"

class Configuration::Settings::Networks
  getter errors : Array(String)
  getter networks : Array(String)
  getter network_type : String

  def initialize(@errors, @networks, @network_type)
  end

  def validate
    if @networks
      if @networks.empty?
        errors << "#{network_type} allowed networks are required"
      else
        validate_networks
        validate_current_ip_must_be_included_in_at_least_one_network
      end
    else
      errors << "#{network_type} allowed networks are required"
    end
  end

  private def validate_networks
    @networks.each do |cidr|
      validate_cidr_network(cidr)
    end
  end

  private def validate_cidr_network(cidr : String)
    begin
      IPAddress.new(cidr).network?
    rescue ArgumentError
      errors << "#{network_type} allowed network #{cidr} is not a valid network in CIDR notation"
    end
  end

  private def validate_current_ip_must_be_included_in_at_least_one_network
    current_ip = IPAddress.new("127.0.0.1")

    begin
      current_ip = IPAddress.new(Crest.get("http://whatismyip.akamai.com").body)
    rescue ex : Crest::RequestFailed
      errors << "Unable to determine your current IP (necessary to validate allowed networks for SSH and API)"
      return
    end

    included = false

    @networks.each do |cidr|
      included = check_current_ip_in_network(cidr, current_ip, included)
    end

    unless included
      errors << "Your current IP #{current_ip} must belong to at least one of the #{network_type} allowed networks"
    end
  end

  private def check_current_ip_in_network(cidr : String, current_ip : IPAddress, included : Bool) : Bool
    begin
      network = IPAddress.new(cidr).network

      if network.includes? current_ip
        included = true
      end
    rescue ex: ArgumentError
      if ex.message =~ /Invalid netmask/
        errors << "#{network_type} allowed network #{cidr} has an invalid netmark"
      else
        errors << "#{network_type} allowed network #{cidr} is not a valid network in CIDR notation"
      end
    end
    included
  end
end
