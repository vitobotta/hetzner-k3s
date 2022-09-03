require "ipaddress"
require "crest"

module IPAddress
  class IPv4
    def includes?(other : IPv6)
      false
    end

    def includes?(*others : IPv6)
      false
    end

    def includes?(others : Array(IPv6))
      false
    end
  end

  class IPv6
    def includes?(other : IPv4)
      false
    end

    def includes?(*others : IPv4)
      false
    end

    def includes?(others : Array(IPv4))
      false
    end
  end
end


class Network
  getter cidr : String
  getter errors : Array(String)
  getter network_type : String

  def initialize(cidr : String, network_type : String)
    @cidr = cidr
    @network_type = network_type
    @errors = [] of String
  end

  def validate
    begin
      IPAddress.new(cidr).network?
    rescue ArgumentError
      errors << "#{network_type} allowed network #{cidr} is not a valid network in CIDR notation"
      return errors
    end

    current_ip = IPAddress.new("127.0.0.1")

    begin
      current_ip = IPAddress.new(Crest.get("http://whatismyip.akamai.com").body)
    rescue ex : Crest::RequestFailed
      errors << "Unable to verify if your current IP belongs to the #{network_type} allowed network #{cidr}"
      return errors
    end

    begin
      network = IPAddress.new(cidr).network

      unless network.includes? current_ip
        errors << "Your current IP #{current_ip} does not belong to the #{network_type} allowed network #{cidr}"
        return errors
      end
    rescue ex: ArgumentError
      if ex.message =~ /Invalid netmask/
        errors << "#{network_type} allowed network #{cidr} has an invalid netmark"
      else
        errors << "#{network_type} allowed network #{cidr} is not a valid network in CIDR notation"
      end
      return errors
    end

    errors
  end
end
