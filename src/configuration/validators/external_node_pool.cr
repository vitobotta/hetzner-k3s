require "../models/worker_node_pool"
require "../models/external_config"
require "../main"

class Configuration::Validators::ExternalNodePool
  getter errors : Array(String)
  getter pool : Configuration::Models::WorkerNodePool
  getter settings : Configuration::Main
  getter all_generated_hostnames : Array(String)

  def initialize(@errors, @pool, @settings, @all_generated_hostnames)
  end

  def validate
    # Rule #1: private network must be disabled
    unless !settings.networking.private_network.enabled
      errors << "External node pool '#{pool.name}' requires the private network to be disabled (set networking.private_network.enabled to false)"
    end

    # Rule #2: local firewall must be enabled
    unless settings.networking.public_network.use_local_firewall
      errors << "External node pool '#{pool.name}' requires the local firewall (set networking.public_network.use_local_firewall to true)"
    end

    # Rule #6: no extraneous Hetzner-specific fields
    validate_no_hetzner_fields

    # Validate external config is present and has nodes
    external_config = pool.external
    if external_config.nil? || external_config.nodes.empty?
      errors << "External node pool '#{pool.name}' must have at least one node in the external.nodes section"
      return
    end

    # Instance count must match number of nodes
    if pool.instance_count != external_config.nodes.size
      errors << "External node pool '#{pool.name}' has instance_count=#{pool.instance_count} but #{external_config.nodes.size} node(s) in external.nodes. These must match."
    end

    # Index validation: indices must be unique within the pool and in range 1..instance_count
    indices = external_config.nodes.map(&.index)
    if indices.uniq.size != indices.size
      errors << "External node pool '#{pool.name}' has duplicate node indices: #{indices.tally.select { |_, c| c > 1 }.keys.join(", ")}"
    end
    expected_range = (1..pool.instance_count).to_a
    invalid_indices = indices - expected_range
    unless invalid_indices.empty?
      errors << "External node pool '#{pool.name}' has out-of-range node indices: #{invalid_indices.join(", ")}. Indices must be in range 1..#{pool.instance_count}."
    end
    # Host IPs must be valid IPv4 addresses (firewall ipset only accepts IP/CIDR, not DNS names)
    hosts = external_config.nodes.map(&.host)
    invalid_hosts = hosts.reject { |host| host =~ /^(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})$/ && $~.captures.all? { |octet| octet.try(&.to_i).try { |n| n >= 0 && n <= 255 } } }
    unless invalid_hosts.empty?
      errors << "External node pool '#{pool.name}' has invalid host values (must be valid IPv4 addresses): #{invalid_hosts.join(", ")}"
    end

    # Host IPs must be unique within the pool
    if hosts.uniq.size != hosts.size
      errors << "External node pool '#{pool.name}' has duplicate node hosts: #{hosts.tally.select { |_, c| c > 1 }.keys.join(", ")}"
    end
  end

  private def validate_no_hetzner_fields
    unexpected = [] of String
    unexpected << "image" unless pool.image.nil?
    unexpected << "autoscaling" unless pool.autoscaling.nil?
    unexpected << "grow_root_partition_automatically" unless pool.grow_root_partition_automatically.nil?
    unexpected << "legacy_instance_type" unless pool.legacy_instance_type.blank?
    # location has a default "fsn1" so we can't detect explicit setting — ignored for external pools
    unless unexpected.empty?
      errors << "External node pool '#{pool.name}' must not include Hetzner-specific fields: #{unexpected.join(", ")}"
    end
  end
end
