require "../../configuration/main"
require "crinja"

class Kubernetes::Script::LabelsAndTaintsGenerator
  EXTERNAL_NODE_LABEL          = "hetzner-k3s.io/external"
  EXTERNAL_NODE_PROVIDER_LABEL = "hetzner-k3s.io/external-provider"
  EXCLUDE_FROM_LB_LABEL        = "node.kubernetes.io/exclude-from-external-load-balancers"

  def self.build_labels(label_collection, automatic_labels = [] of Tuple(String, String))
    labels = label_collection.compact_map do |label|
      next if label.key.nil? || label.value.nil?
      key = escape(label.key.not_nil!)
      value = escape(label.value.not_nil!)
      "--node-label \"#{key}=#{value}\""
    end

    automatic_labels.each do |key, value|
      labels << "--node-label \"#{escape(key)}=#{escape(value)}\""
    end

    result = labels.empty? ? "" : " #{labels.join(" ")} "
    Crinja::SafeString.new(result)
  end

  def self.build_taints(taint_collection)
    taints = taint_collection.compact_map do |taint|
      next if taint.key.nil? || taint.value.nil?
      key, value, effect = parse_taint(taint)
      "--node-taint \"#{key}=#{value}:#{effect}\""
    end
    result = taints.empty? ? "" : " #{taints.join(" ")} "
    Crinja::SafeString.new(result)
  end

  def self.labels_and_taints(settings, pool)
    pool = pool.not_nil!
    labels = build_labels(pool.labels, automatic_labels(pool))
    taints = build_taints(pool.taints)
    result = " #{labels} #{taints} "
    Crinja::SafeString.new(result)
  end
  private def self.automatic_labels(pool) : Array(Tuple(String, String))
    return [] of Tuple(String, String) unless pool.external?

    external_config = pool.external.not_nil!
    labels = [
      {EXTERNAL_NODE_LABEL, "true"},
      {EXTERNAL_NODE_PROVIDER_LABEL, external_config.provider},
    ] of Tuple(String, String)

    # Generic external nodes use a provider ID that HCCM does not understand,
    # so they cannot be LoadBalancer targets. Exclude them to avoid warnings.
    labels << {EXCLUDE_FROM_LB_LABEL, "true"} if external_config.generic?

    labels
  end

  private def self.parse_taint(taint)
    key = escape(taint.key.not_nil!)
    parts = taint.value.not_nil!.split(":")
    value = escape(parts[0])
    effect = parts.size > 1 ? parts[1] : "NoSchedule"
    {key, value, effect}
  end

  private def self.escape(str)
    str.gsub("\"", "\\\"")
  end
end
