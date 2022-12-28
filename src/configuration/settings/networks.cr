require "../../network"

class Configuration::Settings::Networks
  getter errors : Array(String)
  getter networks : Array(String)

  def initialize(@errors, @networks)
  end

  def validate(network_type : String)
    if networks
      if networks.empty?
        errors << "#{network_type} allowed networks are required"
      else
        networks.each do |network|
          @errors = errors + Network.new(network, network_type).validate
        end
      end
    else
      errors << "#{network_type} allowed networks are required"
    end
  end
end
