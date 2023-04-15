require "yaml"
require "crest"

require "./main"

require "../hetzner/client"
require "../hetzner/server_type"
require "../hetzner/location"

require "./settings/configuration_file_path"
require "./settings/cluster_name"
require "./settings/kubeconfig_path"
require "./settings/k3s_version"
require "./settings/new_k3s_version"
require "./settings/public_ssh_key_path"
require "./settings/private_ssh_key_path"
require "./settings/networks"
require "./settings/existing_network_name"
require "./settings/node_pool"
require "./settings/node_pool/autoscaling"
require "./settings/node_pool/pool_name"
require "./settings/node_pool/instance_type"
require "./settings/node_pool/location"
require "./settings/node_pool/instance_count"
require "./settings/node_pool/node_labels"
require "./settings/node_pool/node_taints"


class Configuration::Loader
  getter hetzner_client : Hetzner::Client?
  getter errors : Array(String) = [] of String
  getter settings : Configuration::Main

  getter hetzner_client : Hetzner::Client do
    if settings.hetzner_token.blank?
      errors << "Hetzner API token is missing, please set it in the configuration file or in the environment variable HCLOUD_TOKEN"
      print_errors
      exit 1
    end

    Hetzner::Client.new(settings.hetzner_token)
  end

  getter public_ssh_key_path do
    Path[settings.public_ssh_key_path].expand(home: true).to_s
  end

  getter private_ssh_key_path do
    Path[settings.private_ssh_key_path].expand(home: true).to_s
  end

  getter kubeconfig_path do
    Path[settings.kubeconfig_path].expand(home: true).to_s
  end

  getter masters_location : String | Nil do
    settings.masters_pool.try &.location
  end

  getter server_types : Array(Hetzner::ServerType) do
    server_types = hetzner_client.server_types
    handle_api_errors(server_types, "Cannot fetch server types with Hetzner API, please try again later")
  end

  getter locations : Array(Hetzner::Location) do
    locations = hetzner_client.locations
    handle_api_errors(locations, "Cannot fetch locations with Hetzner API, please try again later")
  end

  getter new_k3s_version : String?
  getter configuration_file_path : String

  private property server_types_loaded : Bool = false
  private property locations_loaded : Bool = false

  def initialize(@configuration_file_path, @new_k3s_version)
    @settings = Configuration::Main.from_yaml(File.read(configuration_file_path))

    Settings::ConfigurationFilePath.new(errors, configuration_file_path).validate

    print_errors unless errors.empty?
  end

  def validate(command)
    print "Validating configuration..."

    Settings::ClusterName.new(errors, settings.cluster_name).validate

    validate_command_specific_settings(command)

    print_validation_result
  end

  private def validate_command_specific_settings(command)
    case command
    when :create
      validate_create_settings
    when :delete
    when :upgrade
      validate_upgrade_settings
    end
  end

  private def validate_create_settings
    Settings::KubeconfigPath.new(errors, kubeconfig_path, file_must_exist: false).validate
    Settings::K3sVersion.new(errors, settings.k3s_version).validate
    Settings::PublicSSHKeyPath.new(errors, public_ssh_key_path).validate
    Settings::PrivateSSHKeyPath.new(errors, private_ssh_key_path).validate
    Settings::ExistingNetworkName.new(errors, hetzner_client, settings.existing_network).validate
    Settings::Networks.new(errors, settings.ssh_allowed_networks, "SSH").validate
    Settings::Networks.new(errors, settings.api_allowed_networks, "API").validate
    validate_masters_pool
    validate_worker_node_pools
  end

  private def validate_upgrade_settings
    Settings::KubeconfigPath.new(errors, kubeconfig_path, file_must_exist: true).validate
    Settings::NewK3sVersion.new(errors, settings.k3s_version, new_k3s_version).validate
  end

  private def print_validation_result
    if errors.empty?
      puts "...configuration seems valid."
    else
      print_errors
      exit 1
    end
  end

  private def validate_masters_pool
    Settings::NodePool.new(
      errors: errors,
      pool: settings.masters_pool,
      pool_type: :masters,
      masters_location: masters_location,
      server_types: server_types,
      locations: locations
    ).validate
  end

  private def validate_worker_node_pools
    if settings.worker_node_pools.nil?
      errors << "`worker_node_pools` is required if workloads cannot be scheduled on masters" unless settings.schedule_workloads_on_masters
      return
    end

    node_pools = settings.worker_node_pools
    validate_node_pools_configuration(node_pools)
  end

  private def validate_node_pools_configuration(node_pools)
    if node_pools.empty?
      errors << "At least one worker node pool is required in order to schedule workloads" unless settings.schedule_workloads_on_masters
    else
      validate_unique_node_pool_names(node_pools)
      validate_each_node_pool(node_pools)
    end
  end

  private def validate_unique_node_pool_names(node_pools)
    worker_node_pool_names = node_pools.map(&.name)
    errors << "Each worker node pool must have a unique name" if worker_node_pool_names.uniq.size != node_pools.size
  end

  private def validate_each_node_pool(node_pools)
    node_pools.each do |worker_node_pool|
      Settings::NodePool.new(
        errors: errors,
        pool: worker_node_pool,
        pool_type: :workers,
        masters_location: masters_location,
        server_types: server_types,
        locations: locations
      ).validate
    end
  end

  private def print_errors
    return if errors.empty?

    puts "\nSome information in the configuration file requires your attention:"

    errors.each do |error|
      STDERR.puts "  - #{error}"
    end

    exit 1
  end

  private def handle_api_errors(data, error_message)
    if data.empty?
      errors << error_message
      print_errors
      exit 1
    end

    data
  end
end
