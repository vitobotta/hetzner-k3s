class Configuration::NetworkingComponents::AllowedNetworks
  include YAML::Serializable
  include YAML::Serializable::Unmapped

  getter ssh : Array(String) = ["0.0.0.0/0"]
  getter api : Array(String) = ["0.0.0.0/0"]

  def initialize
  end

  def validate(errors)
    validate_networks(errors, ssh, "SSH")
    validate_networks(errors, api, "API")
  end

  private def current_ip
    @current_ip ||= begin
      Crest.get("https://ipinfo.io/ip").body
    rescue Crest::RequestFailed
      errors << "Unable to determine your current IP (necessary to validate allowed networks for SSH and API)"
      nil
    end
  end

  private def validate_current_ip_must_be_included_in_at_least_one_network(errors, networks, network_type)
    return if current_ip.nil?

    included = false

    networks.each do |cidr|
      included = check_current_ip_in_network(errors, cidr, current_ip, included, network_type)
    end

    unless included
      errors << "Your current IP #{current_ip} must belong to at least one of the #{network_type} allowed networks"
    end
  end

  private def check_current_ip_in_network(errors, cidr : String, current_ip : IPAddress, included : Bool, network_type) : Bool
    begin
      network = IPAddress.new(cidr).network

      included = true = network.includes?(current_ip)
    rescue ex: ArgumentError
      if ex.message =~ /Invalid netmask/
        errors << "#{network_type} allowed network #{cidr} has an invalid netmask"
      else
        errors << "#{network_type} allowed network #{cidr} is not a valid network in CIDR notation"
      end
    end
    included
  end

  private def validate_cidr_network(errors, cidr : String, network_type)
    begin
      IPAddress.new(cidr).network?
    rescue ArgumentError
      errors << "#{network_type} allowed network #{cidr} is not a valid network in CIDR notation"
    end
  end

  private def validate_networks(errors, networks, network_type)
    if networks.nil? || networks.empty?
      errors << "#{network_type} allowed networks are required"
    else
      networks.each do |cidr|
        validate_cidr_network(errors, cidr, network_type)
      end

      validate_current_ip_must_be_included_in_at_least_one_network(errors, networks, network_type)
    end
  end
end
