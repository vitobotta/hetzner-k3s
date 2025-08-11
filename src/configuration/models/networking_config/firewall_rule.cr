require "ipaddress"

class Configuration::Models::NetworkingConfig::FirewallRule
  include YAML::Serializable
  include YAML::Serializable::Unmapped

  # Optional human-readable description for the rule (used in Hetzner firewall description field)
  getter description : String? = nil
  # Supported protocols: tcp, udp, icmp, esp, gre – defaults to tcp for backwards compatibility / convenience
  getter protocol : String = "tcp"
  # Direction of traffic: "in" or "out". Both directions are supported by Hetzner Cloud firewalls.
  getter direction : String = "in"
  # A single port ("80"), a range ("30000-32767"), or "any" for all ports (Hetzner API syntax)
  getter port : String = "any"
  # CIDR ranges allowed for incoming traffic when direction is "in"
  getter source_ips : Array(String) = [] of String
  # CIDR ranges allowed for outgoing traffic when direction is "out"
  getter destination_ips : Array(String) = [] of String

  def initialize
  end

  # Adds validation errors to the shared errors array.
  def validate(errors : Array(String))
    validate_protocol(errors)
    validate_direction(errors)
    validate_port(errors)

    if direction == "in"
      validate_ips(errors, source_ips, "source_ips", required: true)
    else
      validate_ips(errors, destination_ips, "destination_ips", required: true)
    end
  end

  # Returns a sane default description if the user did not specify one.
  def effective_description : String
    desc = @description
    desc && !desc.empty? ? desc : "Allow #{protocol.upcase} #{port}"
  end

  private def validate_protocol(errors : Array(String))
    allowed = %w(tcp udp icmp esp gre)
    unless allowed.includes?(protocol)
      errors << "Firewall rule protocol must be one of #{allowed.join(", ")} (given #{protocol})"
    end
  end

  private def validate_direction(errors : Array(String))
    allowed = %w(in out)
    unless allowed.includes?(direction)
      errors << "Firewall rule direction must be 'in' or 'out' (given #{direction})"
    end
  end

  private def validate_port(errors : Array(String))
    # Port is only relevant for TCP and UDP; all other protocols ignore the port field.
    return if protocol != "tcp" && protocol != "udp"

    # Valid formats: "any", "80", "30000-32767"
    unless port == "any" || port =~ /^\d+(?:-\d+)?$/
      errors << "Port '#{port}' is not a valid port value (expect single port, range, or 'any')"
    end
  end

  # Validates each CIDR in the list and ensures presence if required
  private def validate_ips(errors : Array(String), ips : Array(String), label : String, required : Bool = false)
    return errors << "#{label} must contain at least one CIDR" if required && (ips.nil? || ips.empty?)

    if ips.size > 100
      # Hetzner Cloud currently allows up to 100 CIDR blocks per firewall rule
      errors << "#{label} supports a maximum of 100 CIDR blocks (got #{ips.size})"
    end

    ips.each { |cidr| validate_cidr_network(errors, cidr) }
  end

  private def validate_cidr_network(errors : Array(String), cidr : String)
    IPAddress.new(cidr).network?
  rescue ArgumentError
    errors << "Custom firewall rule network #{cidr} is not a valid CIDR"
  end
end
