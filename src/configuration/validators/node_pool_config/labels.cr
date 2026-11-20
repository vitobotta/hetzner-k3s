require "../../models/node_pool_config/label"

class Configuration::Validators::NodePoolConfig::Labels
  RESERVED_LABEL_KEYS = [
    "hetzner-k3s.io/external",
    "hetzner-k3s.io/external-provider",
    "node.kubernetes.io/exclude-from-external-load-balancers",
  ]

  getter errors : Array(String)
  getter pool_type : Symbol
  getter labels : Array(Configuration::Models::NodePoolConfig::Label)?

  def initialize(@errors, @pool_type, @labels)
  end

  def validate
    return unless labels

    labels.try &.each do |label|
      if label.key.nil? || label.value.nil?
        errors << "#{pool_type} has invalid labels"
        break
      end

      if RESERVED_LABEL_KEYS.includes?(label.key)
        errors << "#{pool_type} uses reserved label '#{label.key}'. hetzner-k3s sets this label automatically."
      end
    end
  end
end
