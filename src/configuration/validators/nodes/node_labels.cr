require "../../models/node_pool_config/label"

class Configuration::Validators::Nodes::NodeLabels
  getter errors : Array(String)
  getter pool_type : Symbol
  getter labels : Array(Configuration::Models::NodePoolConfig::Label)?

  def initialize(@errors, @pool_type, @labels)
  end

  def validate
    return unless labels

    labels.try &.each do |label|
      next unless label.key.nil? || label.value.nil?

      errors << "#{pool_type} has invalid labels"
      break
    end
  end
end
