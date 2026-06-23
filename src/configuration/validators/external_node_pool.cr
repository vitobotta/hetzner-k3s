require "../models/worker_node_pool"
require "../models/external_config"
require "../main"

class Configuration::Validators::ExternalNodePool
  getter errors : Array(String)
  getter pool : Configuration::Models::WorkerNodePool
  getter settings : Configuration::Main
  def initialize(@errors, @pool, @settings)
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

    validate_provider(external_config)

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

    # Host IPs must be unique across all external pools
    duplicate_hosts_across_pools = external_hosts_in_other_pools & hosts
    unless duplicate_hosts_across_pools.empty?
      errors << "External node pool '#{pool.name}' reuses host values already used by another external pool: #{duplicate_hosts_across_pools.join(", ")}"
    end

    validate_robot_config(external_config) if external_config.robot?
  end

  private def validate_provider(external_config)
    allowed_providers = [
      Configuration::Models::ExternalConfig::PROVIDER_GENERIC,
      Configuration::Models::ExternalConfig::PROVIDER_ROBOT,
    ]
    return if allowed_providers.includes?(external_config.provider)

    errors << "External node pool '#{pool.name}' has invalid external.provider '#{external_config.provider}'. Allowed values: #{allowed_providers.join(", ")}"
  end

  private def validate_robot_config(external_config)
    if external_config.robot_user.blank? || external_config.robot_password.blank?
      errors << "External node pool '#{pool.name}' uses external.provider: robot but Robot credentials are missing. Set external.robot_user/external.robot_password or ROBOT_USER/ROBOT_PASSWORD."
    end

    unless settings.addons.cloud_controller_manager.enabled?
      errors << "External node pool '#{pool.name}' uses external.provider: robot but addons.cloud_controller_manager.enabled is false. Robot nodes require the Hetzner Cloud Controller Manager."
    end

    if robot_credentials_conflict?(external_config)
      errors << "External node pool '#{pool.name}' uses Robot credentials that differ from another external Robot pool. All Robot pools must use the same credentials because HCCM accepts one Robot account."
    end

    missing_server_numbers = external_config.nodes.select { |node| node.robot_server_number.nil? }.map(&.host)
    unless missing_server_numbers.empty?
      errors << "External node pool '#{pool.name}' uses external.provider: robot but nodes are missing robot_server_number: #{missing_server_numbers.join(", ")}"
    end

    server_numbers = external_config.nodes.compact_map(&.robot_server_number)
    if server_numbers.uniq.size != server_numbers.size
      errors << "External node pool '#{pool.name}' has duplicate robot_server_number values: #{server_numbers.tally.select { |_, c| c > 1 }.keys.join(", ")}"
    end

    duplicate_server_numbers = robot_server_numbers_in_other_pools & server_numbers
    unless duplicate_server_numbers.empty?
      errors << "External node pool '#{pool.name}' reuses robot_server_number values already used by another external Robot pool: #{duplicate_server_numbers.join(", ")}"
    end
  end

  private def robot_credentials_conflict?(current_external_config) : Bool
    settings.worker_node_pools.any? do |other_pool|
      next false if other_pool == pool
      external = other_pool.external
      next false unless other_pool.external? && external && external.robot?

      external.robot_user != current_external_config.robot_user || external.robot_password != current_external_config.robot_password
    end
  end

  private def robot_server_numbers_in_other_pools : Array(Int32)
    settings.worker_node_pools.flat_map do |other_pool|
      next [] of Int32 if other_pool == pool
      external = other_pool.external
      next [] of Int32 unless other_pool.external? && external && external.robot?

      external.nodes.compact_map(&.robot_server_number)
    end
  end

  private def external_hosts_in_other_pools : Array(String)
    settings.worker_node_pools.flat_map do |other_pool|
      next [] of String if other_pool == pool
      external = other_pool.external
      next [] of String unless other_pool.external? && external

      external.nodes.map(&.host)
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
