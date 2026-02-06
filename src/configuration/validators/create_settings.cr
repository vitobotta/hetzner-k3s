require "./kubeconfig_path"
require "./k3s_version"
require "./datastore"
require "./networking"
require "../main"
require "../models/networking"
require "../models/datastore"
require "../models/master_node_pool"
require "../models/worker_node_pool"
require "../../hetzner/client"
require "./masters_pool"
require "./worker_node_pools"
require "./kubectl_presence"
require "./helm_presence"

class Configuration::Validators::CreateSettings
  getter errors : Array(String) = [] of String
  getter settings : Configuration::Main
  getter kubeconfig_path : String
  getter hetzner_client : Hetzner::Client
  getter masters_pool : Configuration::Models::MasterNodePool
  getter instance_types : Array(Hetzner::InstanceType)
  getter all_locations : Array(Hetzner::Location)
  getter skip_current_ip_validation : Bool = false

  def initialize(
    @errors,
    @settings,
    @kubeconfig_path,
    @hetzner_client,
    @masters_pool,
    @instance_types,
    @all_locations,
    @skip_current_ip_validation = false
  )
  end

  def validate
    Configuration::Validators::KubeconfigPath.new(errors, kubeconfig_path, file_must_exist: false).validate

    Configuration::Validators::K3sVersion.new(errors, settings.k3s_version).validate

    Configuration::Validators::Datastore.new(errors, settings.datastore).validate

    Configuration::Validators::Networking.new(
      errors,
      settings.networking,
      settings,
      hetzner_client,
      settings.networking.private_network,
      skip_current_ip_validation: skip_current_ip_validation
    ).validate

    Configuration::Validators::MastersPool.new(
      errors: errors,
      masters_pool: masters_pool,
      instance_types: instance_types,
      all_locations: all_locations,
      datastore: settings.datastore,
      private_network_enabled: settings.networking.private_network.enabled
    ).validate

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

    Configuration::Validators::KubectlPresence.new(errors).validate

    Configuration::Validators::HelmPresence.new(errors).validate
  end
end
