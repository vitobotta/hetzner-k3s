require "../../node_label"

class Configuration::Settings::NodePool::NodeLabels
  getter errors : Array(String)
  getter pool_type : Symbol
  getter labels : Array(Configuration::NodeLabel)?

  def initialize(@errors, @pool_type, @labels)
  end

  def validate
    given_labels = labels

    return unless given_labels

    given_labels.each do |label|
      unless (label.key && label.value)
        errors << "#{pool_type} has invalid labels"
        break
      end
    end
  end
end
