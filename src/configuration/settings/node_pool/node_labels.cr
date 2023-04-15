require "../../node_label"

class Configuration::Settings::NodePool::NodeLabels
  getter errors : Array(String)
  getter pool_type : Symbol
  getter labels : Array(Configuration::NodeLabel)?

  def initialize(@errors, @pool_type, @labels)
  end

  def validate
    return unless labels

    labels.try &.each do |label|
      if label.key.nil? || label.value.nil?
        errors << "#{pool_type} has invalid labels"
        break
      end
    end
  end
end
