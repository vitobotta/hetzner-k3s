require "ipaddress"

class Configuration::Settings::PrivateNetwork
  getter enabled : Bool = true
  getter subnet : String = "10.0.0.0/16"

  def initialize(@enabled, @subnet)
  end

  def validate
    begin
      IPAddress.new(subnet).network?
    rescue ArgumentError
      errors << "private network subnet #{cidr} is not a valid network in CIDR notation"
    end
  end
end
