require "ipaddress"

class Configuration::Validators::NetworkingConfig::FirewallRule
  getter errors : Array(String)
  getter rule : Configuration::Models::NetworkingConfig::FirewallRule

  def initialize(@errors, @rule)
  end

  def validate
    validate_protocol
    validate_direction
    validate_port

    if rule.direction == "in"
      validate_ips(rule.source_ips, "source_ips", required: true)
    else
      validate_ips(rule.destination_ips, "destination_ips", required: true)
    end
  end

  private def validate_protocol
    allowed = %w(tcp udp icmp esp gre)
    unless allowed.includes?(rule.protocol)
      errors << "Firewall rule protocol must be one of #{allowed.join(", ")} (given #{rule.protocol})"
    end
  end

  private def validate_direction
    allowed = %w(in out)
    unless allowed.includes?(rule.direction)
      errors << "Firewall rule direction must be 'in' or 'out' (given #{rule.direction})"
    end
  end

  private def validate_port
    # Port is only relevant for TCP and UDP; all other protocols ignore the port field.
    return if rule.protocol != "tcp" && rule.protocol != "udp"

    unless rule.port == "any" || rule.port =~ /^\d+(?:-\d+)?$/
      errors << "Port '#{rule.port}' is not a valid port value (expect single port, range, or 'any')"
    end
  end

  private def validate_ips(ips : Array(String), label : String, required : Bool = false)
    if required && (ips.nil? || ips.empty?)
      errors << "#{label} must contain at least one CIDR"
      return
    end

    if ips.size > 100
      errors << "#{label} supports a maximum of 100 CIDR blocks (got #{ips.size})"
    end

    ips.each { |cidr| validate_cidr_network(cidr) }
  end

  private def validate_cidr_network(cidr : String)
    IPAddress.new(cidr).network?
  rescue ArgumentError
    errors << "Custom firewall rule network #{cidr} is not a valid CIDR"
  end
end
