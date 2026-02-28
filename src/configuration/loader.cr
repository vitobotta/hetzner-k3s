require "yaml"

require "./main"
require "../hetzner/client"

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
require "./validators/masters_pool"
require "./validators/kubectl_presence"
require "./validators/helm_presence"
require "./validators/create_settings"
require "./validators/upgrade_settings"
require "./validators/run_settings"
require "./validators/command_specific_settings"
require "../util"

class Configuration::Loader
  include Util

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
  getter skip_current_ip_validation : Bool = false

  private property force : Bool = false

  def initialize(@configuration_file_path, @new_k3s_version, @force, @skip_current_ip_validation = false)
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
    Configuration::Validators::CommandSpecificSettings.new(
      errors: errors,
      settings: settings,
      kubeconfig_path: kubeconfig_path,
      hetzner_client: hetzner_client,
      masters_pool: masters_pool,
      instance_types: instance_types,
      all_locations: all_locations,
      new_k3s_version: new_k3s_version,
      skip_current_ip_validation: skip_current_ip_validation
    ).validate(command)
  end

  private def print_validation_result
    if errors.empty?
      log_line "...configuration seems valid."
    else
      print_errors
      exit 1
    end
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
