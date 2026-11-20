require "crest"
require "ipaddress"

require "../../models/networking_config/allowed_networks"
require "./firewall_rule"

class Configuration::Validators::NetworkingConfig::AllowedNetworks
  IP_LOOKUP_CONNECT_TIMEOUT = 5.seconds
  IP_LOOKUP_READ_TIMEOUT    = 10.seconds

  getter errors : Array(String) = [] of String
  getter allowed_networks : Configuration::Models::NetworkingConfig::AllowedNetworks
  getter skip_current_ip_validation : Bool = false

  def initialize(@errors, @allowed_networks, @skip_current_ip_validation = false)
  end

  def validate
    validate_networks(errors, allowed_networks.ssh, "SSH")
    validate_networks(errors, allowed_networks.api, "API")
    validate_custom_firewall_rules(errors, allowed_networks.custom_firewall_rules)
  end

  private def validate_current_ip_must_be_included_in_at_least_one_network(errors, networks, network_type)
    current_ip = nil

    begin
      # Explicit timeouts: without them an unreachable ipinfo.io stalls validation before anything
      # else happens, and the message below is the only place the cause would be visible.
      current_ip = IPAddress.new(
        Crest.get("https://ipinfo.io/ip", connect_timeout: IP_LOOKUP_CONNECT_TIMEOUT, read_timeout: IP_LOOKUP_READ_TIMEOUT).body
      )
    rescue ex : Crest::RequestFailed | IO::Error | Socket::Error | ArgumentError
      errors << "Unable to determine your current IP (necessary to validate allowed networks for SSH and API): #{ex.message}. Use --skip-ip-validation to skip the check."
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

    return if skip_current_ip_validation

    validate_current_ip_must_be_included_in_at_least_one_network(errors, networks, network_type)
  end

  private def validate_custom_firewall_rules(errors, rules)
    return if rules.empty?

    # Hetzner Cloud supports maximum 50 rules per firewall; default rules use ~10
    default_rule_slots = 10
    if rules.size + default_rule_slots > 50
      errors << "The sum of default firewall rules (~#{default_rule_slots}) and your custom ones (#{rules.size}) exceeds the 50-rule limit imposed by Hetzner Cloud. Please reduce the number of custom firewall rules."
    end

    rules.each do |rule|
      Configuration::Validators::NetworkingConfig::FirewallRule.new(errors, rule).validate
    end
  end
end
