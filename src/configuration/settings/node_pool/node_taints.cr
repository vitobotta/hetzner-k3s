require "../../node_taint"

class Configuration::Settings::NodePool::NodeTaints
  getter errors : Array(String)
  getter pool_type : Symbol
  getter taints : Array(Configuration::NodeTaint)?

  def initialize(@errors, @pool_type, @taints)
  end

  def validate
    given_taints = taints

    return unless given_taints

    given_taints.each do |mark|
      unless (mark.key && mark.value)
        errors << "#{pool_type} has invalid taints"
        break
      end
    end
  end
end
