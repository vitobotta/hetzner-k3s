require "../../models/addons_config/coredns"

class Configuration::Validators::AddonsConfig::CoreDNS
  MIN_REPLICAS =  1
  MAX_REPLICAS = 10

  CPU_QUANTITY    = /\A\d+(\.\d+)?m?\z/
  MEMORY_QUANTITY = /\A\d+(\.\d+)?(Ki|Mi|Gi|Ti|K|M|G|T|m)?\z/

  MEMORY_FACTORS = {
    "Ki" => 1024.0,
    "Mi" => 1024.0 * 1024,
    "Gi" => 1024.0 * 1024 * 1024,
    "Ti" => 1024.0 * 1024 * 1024 * 1024,
    "K"  => 1000.0,
    "M"  => 1000.0 * 1000,
    "G"  => 1000.0 * 1000 * 1000,
    "T"  => 1000.0 * 1000 * 1000 * 1000,
    "m"  => 0.001,
  }

  getter errors : Array(String)
  getter coredns : Configuration::Models::AddonsConfig::CoreDNS

  def initialize(@errors, @coredns)
  end

  def validate
    validate_replicas
    validate_image
    validate_quantity("cpu", coredns.resources.requests.cpu, coredns.resources.limits.cpu, CPU_QUANTITY)
    validate_quantity("memory", coredns.resources.requests.memory, coredns.resources.limits.memory, MEMORY_QUANTITY)
  end

  private def validate_replicas
    replicas = coredns.replicas
    return if replicas.nil?
    return if MIN_REPLICAS <= replicas <= MAX_REPLICAS

    errors << "addons.coredns.replicas must be between #{MIN_REPLICAS} and #{MAX_REPLICAS} (found: #{replicas})"
  end

  private def validate_image
    errors << "addons.coredns.image cannot be empty" if coredns.image.strip.empty?
  end

  private def validate_quantity(resource : String, request : String?, limit : String?, format : Regex)
    {request, limit}.each do |value|
      next if value.nil? || value.strip.empty?
      next if value.strip.matches?(format)

      errors << "addons.coredns.resources has an invalid #{resource} quantity '#{value}'"
    end

    return unless request && limit
    return unless request.strip.matches?(format) && limit.strip.matches?(format)

    request_value = quantity_value(resource, request.strip)
    limit_value = quantity_value(resource, limit.strip)
    return if request_value.nil? || limit_value.nil?
    return if request_value <= limit_value

    errors << "addons.coredns.resources.requests.#{resource} (#{request}) must not exceed addons.coredns.resources.limits.#{resource} (#{limit})"
  end

  private def quantity_value(resource : String, value : String) : Float64?
    if resource == "cpu"
      return value.ends_with?("m") ? value[0..-2].to_f / 1000 : value.to_f
    end

    suffix = value.sub(/\A\d+(\.\d+)?/, "")
    factor = suffix.empty? ? 1.0 : MEMORY_FACTORS[suffix]?
    return nil unless factor

    value.chomp(suffix).to_f * factor
  end
end
