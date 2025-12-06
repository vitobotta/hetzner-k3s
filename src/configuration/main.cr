require "yaml"

require "./models/master_node_pool"
require "./models/worker_node_pool"
require "./models/datastore"
require "./models/addons"

class Configuration::Main
  include YAML::Serializable

  getter hetzner_token : String = ENV.fetch("HCLOUD_TOKEN", "")
  getter cluster_name : String
  getter kubeconfig_path : String
  getter k3s_version : String
  getter api_server_hostname : String?
  getter schedule_workloads_on_masters : Bool = false
  getter masters_pool : Configuration::Models::MasterNodePool
  getter worker_node_pools : Array(Configuration::Models::WorkerNodePool) = [] of Configuration::Models::WorkerNodePool
  getter additional_pre_k3s_commands : Array(String) = [] of String
  getter additional_post_k3s_commands : Array(String) = [] of String
  getter additional_packages : Array(String) = [] of String
  getter kube_api_server_args : Array(String) = [] of String
  getter kube_scheduler_args : Array(String) = [] of String
  getter kube_controller_manager_args : Array(String) = [] of String
  getter kube_cloud_controller_manager_args : Array(String) = [] of String
  getter cluster_autoscaler_args : Array(String) = [] of String
  getter kubelet_args : Array(String) = [] of String
  getter kube_proxy_args : Array(String) = [] of String
  getter image : String = "ubuntu-24.04"
  getter autoscaling_image : String?
  getter snapshot_os : String = "default"
  getter networking : Configuration::Models::Networking = Configuration::Models::Networking.new
  getter datastore : Configuration::Models::Datastore = Configuration::Models::Datastore.new
  getter addons : Configuration::Models::Addons = Configuration::Models::Addons.new
  getter include_instance_type_in_instance_name : Bool = false
  getter protect_against_deletion : Bool = true
  getter create_load_balancer_for_the_kubernetes_api : Bool = false
  getter k3s_upgrade_concurrency : Int64 = 1
  getter grow_root_partition_automatically : Bool = true

  def all_kubelet_args
    ["cloud-provider=external", "resolv-conf=/etc/k8s-resolv.conf"] + kubelet_args
  end
end
