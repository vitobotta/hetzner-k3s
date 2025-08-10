require "yaml"
require "crest"

require "./main"

require "../hetzner/client"
require "../hetzner/instance_type"
require "../hetzner/location"

require "./validators/configuration_file_path"
require "./validators/cluster_name"
require "./validators/kubeconfig_path"
require "./validators/k3s_version"
require "./validators/new_k3s_version"
require "./models/networking"
require "./validators/node_pool"
require "./validators/node_pool_config/autoscaling"
require "./validators/node_pool_config/pool_name"
require "./validators/node_pool_config/instance_type"
require "./validators/node_pool_config/location"
require "./validators/node_pool_config/instance_count"
require "./validators/node_pool_config/labels"
require "./validators/node_pool_config/taints"
require "./validators/datastore"
require "./validators/networking_config/allowed_networks"
require "./validators/networking_config/cni_config/cilium"
require "./validators/networking_config/cni"
require "./validators/networking_config/private_network"
require "./validators/networking_config/public_network"
require "./validators/networking_config/ssh"
require "./validators/networking"
require "./validators/worker_node_pools"
require "../util"

class Configuration::Loader
  include Util

  getter hetzner_client : Hetzner::Client?
  getter errors : Array(String) = [] of String
  getter settings : Configuration::Main

  getter hetzner_client : Hetzner::Client do
    if settings.hetzner_token.blank?
      errors << "Hetzner API token is missing, please set it in the configuration file or in the environment variable HCLOUD_TOKEN"
      print_errors
    end

    Hetzner::Client.new(settings.hetzner_token)
  end

  getter kubeconfig_path do
    Path[settings.kubeconfig_path].expand(home: true).to_s
  end

  getter masters_pool : Configuration::Models::MasterNodePool do
    settings.masters_pool
  end

  getter instance_types : Array(Hetzner::InstanceType) do
    hetzner_client.instance_types
  end

  getter all_locations : Array(Hetzner::Location) do
    hetzner_client.locations
  end

  getter new_k3s_version : String?
  getter configuration_file_path : String

  private property instance_types_loaded : Bool = false
  private property locations_loaded : Bool = false
  private property force : Bool = false

  def initialize(@configuration_file_path, @new_k3s_version, @force)
    @settings = Configuration::Main.from_yaml(File.read(configuration_file_path))

    Configuration::Validators::ConfigurationFilePath.new(errors, configuration_file_path).validate

    print_errors unless errors.empty?
  end

  def validate(command)
    log_line "Validating configuration..."

    Configuration::Validators::ClusterName.new(errors, settings.cluster_name).validate

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
    when :run
      validate_run_settings
    end
  end

  private def validate_create_settings
    Configuration::Validators::KubeconfigPath.new(errors, kubeconfig_path, file_must_exist: false).validate
    Configuration::Validators::K3sVersion.new(errors, settings.k3s_version).validate
    Configuration::Validators::Datastore.new(errors, settings.datastore).validate

    Configuration::Validators::Networking.new(errors, settings.networking, settings, hetzner_client, settings.networking.private_network).validate

    validate_masters_pool
    validate_worker_node_pools

    validate_kubectl_presence
    validate_helm_presence
  end

  private def validate_run_settings
    validate_kubectl_presence
  end

  private def validate_upgrade_settings
    Configuration::Validators::KubeconfigPath.new(errors, kubeconfig_path, file_must_exist: true).validate
    Configuration::Validators::NewK3sVersion.new(errors, settings.k3s_version, new_k3s_version).validate

    validate_kubectl_presence
  end

  private def validate_kubectl_presence
    errors << "kubectl is not installed or not in PATH" unless which("kubectl")
  end

  private def validate_helm_presence
    errors << "helm is not installed or not in PATH" unless which("helm")
  end

  private def print_validation_result
    if errors.empty?
      log_line "...configuration seems valid."
    else
      print_errors
      exit 1
    end
  end

  private def validate_masters_pool
    Configuration::Validators::NodePool.new(
      errors: errors,
      pool: settings.masters_pool,
      pool_type: :masters,
      masters_pool: masters_pool,
      instance_types: instance_types,
      all_locations: all_locations,
      datastore: settings.datastore,
      private_network_enabled: settings.networking.private_network.enabled
    ).validate
  end

  private def validate_worker_node_pools
    worker_node_pools = settings.worker_node_pools || [] of Configuration::Models::WorkerNodePool

    Configuration::Validators::WorkerNodePools.new(
      errors: errors,
      worker_node_pools: worker_node_pools,
      schedule_workloads_on_masters: settings.schedule_workloads_on_masters,
      masters_pool: masters_pool,
      instance_types: instance_types,
      all_locations: all_locations,
      datastore: settings.datastore,
      private_network_enabled: settings.networking.private_network.enabled
    ).validate
  end

  private def print_errors
    log_line "Some information in the configuration file requires your attention, aborting."

    errors.uniq.each do |error|
      STDERR.puts "[#{default_log_prefix}]  - #{error}"
    end

    exit 1
  end

  private def default_log_prefix
    "Configuration"
  end
end
