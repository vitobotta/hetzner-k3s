require "yaml"

require "./node_pool"

class Configuration::Main
  include YAML::Serializable

  getter hetzner_token : String = ENV.fetch("HCLOUD_TOKEN", "")
  getter cluster_name : String
  getter kubeconfig_path : String
  getter k3s_version : String
  getter public_ssh_key_path : String
  getter private_ssh_key_path : String
  getter use_ssh_agent : Bool = false
  getter ssh_allowed_networks : Array(String) = [] of String
  getter api_allowed_networks : Array(String) = [] of String
  getter verify_host_key : Bool = false
  getter schedule_workloads_on_masters : Bool = false
  getter enable_encryption : Bool = false
  getter masters_pool : Configuration::NodePool
  getter worker_node_pools : Array(Configuration::NodePool) = [] of Configuration::NodePool
  getter post_create_commands : Array(String) = [] of String
  getter additional_packages : Array(String) = [] of String
  getter kube_api_server_args : Array(String) = [] of String
  getter kube_scheduler_args : Array(String) = [] of String
  getter kube_controller_manager_args : Array(String) = [] of String
  getter kube_cloud_controller_manager_args : Array(String) = [] of String
  getter kubelet_args : Array(String) = [] of String
  getter kube_proxy_args : Array(String) = [] of String
  getter existing_network : String?
  getter image : String = "ubuntu-22.04"
  getter snapshot_os : String = "default"
  getter private_network_subnet : String = "10.0.0.0/16"
end
