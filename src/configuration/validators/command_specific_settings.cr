require "./create_settings"
require "./upgrade_settings"
require "./run_settings"
require "../main"
require "../../hetzner/client"
require "../models/master_node_pool"
require "../../hetzner/instance_type"
require "../../hetzner/location"

class Configuration::Validators::CommandSpecificSettings
  getter errors : Array(String) = [] of String
  getter settings : Configuration::Main
  getter kubeconfig_path : String
  getter hetzner_client : Hetzner::Client
  getter masters_pool : Configuration::Models::MasterNodePool
  getter instance_types : Array(Hetzner::InstanceType)
  getter all_locations : Array(Hetzner::Location)
  getter new_k3s_version : String?

  def initialize(
    @errors,
    @settings,
    @kubeconfig_path,
    @hetzner_client,
    @masters_pool,
    @instance_types,
    @all_locations,
    @new_k3s_version
  )
  end

  def validate(command)
    case command
    when :create
      validate_create_settings
    when :delete
      # No specific validation needed for delete
    when :upgrade
      validate_upgrade_settings
    when :run
      validate_run_settings
    end
  end

  private def validate_create_settings
    Configuration::Validators::CreateSettings.new(
      errors: errors,
      settings: settings,
      kubeconfig_path: kubeconfig_path,
      hetzner_client: hetzner_client,
      masters_pool: masters_pool,
      instance_types: instance_types,
      all_locations: all_locations
    ).validate
  end

  private def validate_upgrade_settings
    Configuration::Validators::UpgradeSettings.new(
      errors: errors,
      settings: settings,
      kubeconfig_path: kubeconfig_path,
      new_k3s_version: new_k3s_version
    ).validate
  end

  private def validate_run_settings
    Configuration::Validators::RunSettings.new(errors).validate
  end
end