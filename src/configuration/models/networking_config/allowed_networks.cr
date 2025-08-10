class Configuration::Models::NetworkingConfig::AllowedNetworks
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

  private def validate_current_ip_must_be_included_in_at_least_one_network(errors, networks, network_type)
    current_ip = IPAddress.new("127.0.0.1")

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
    IPAddress.new(cidr).network.includes?(current_ip)
  rescue ex : ArgumentError
    message = ex.message =~ /Invalid netmask/ ? "#{network_type} allowed network #{cidr} has an invalid netmask" : "#{network_type} allowed network #{cidr} is not a valid network in CIDR notation"
    errors << message
    false
  end

  private def validate_cidr_network(errors, cidr : String, network_type)
    IPAddress.new(cidr).network?
  rescue ArgumentError
    errors << "#{network_type} allowed network #{cidr} is not a valid network in CIDR notation"
  end

  private def validate_networks(errors, networks, network_type)
    return errors << "#{network_type} allowed networks are required" if networks.nil? || networks.empty?

    networks.each { |cidr| validate_cidr_network(errors, cidr, network_type) }
    validate_current_ip_must_be_included_in_at_least_one_network(errors, networks, network_type)
  end
end
