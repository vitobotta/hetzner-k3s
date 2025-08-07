require "../../configuration/main"
require "crinja"

class Kubernetes::Script::LabelsAndTaintsGenerator
  def self.build_labels(label_collection)
    labels = label_collection.compact_map do |label|
      next if label.key.nil? || label.value.nil?
      key = escape(label.key.not_nil!)
      value = escape(label.value.not_nil!)
      "--node-label \"#{key}=#{value}\""
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
    labels = build_labels(pool.labels)
    taints = build_taints(pool.taints)
    result = " #{labels} #{taints} "
    Crinja::SafeString.new(result)
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
