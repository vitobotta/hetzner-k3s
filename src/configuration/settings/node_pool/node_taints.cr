require "../../node_taint"

class Configuration::Settings::NodePool::NodeTaints
  getter errors : Array(String)
  getter pool_type : Symbol
  getter taints : Array(Configuration::NodeTaint)?

  def initialize(@errors, @pool_type, @taints)
  end

  def validate
    return unless taints

    taints.try &.each do |taint|
      if taint.key.nil? || taint.value.nil?
        errors << "#{pool_type} has invalid taints"
        break
      end
    end
  end
end
