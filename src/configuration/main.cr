require "yaml"

require "./node_pool"
require "./datastore"
require "./manifests"
require "./embedded_registry_mirror"
require "./timeouts.cr"

class Configuration::Main
  include YAML::Serializable

  getter hetzner_token : String = ENV.fetch("HCLOUD_TOKEN", "")
  getter cluster_name : String
  getter kubeconfig_path : String
  getter k3s_version : String
  getter api_server_hostname : String?
  getter schedule_workloads_on_masters : Bool = false
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
  getter image : String = "ubuntu-24.04"
  getter autoscaling_image : String?
  getter snapshot_os : String = "default"
  getter networking : Configuration::Networking = Configuration::Networking.new
  getter datastore : Configuration::Datastore = Configuration::Datastore.new
  getter manifests : Configuration::Manifests = Configuration::Manifests.new
  getter embedded_registry_mirror : Configuration::EmbeddedRegistryMirror = Configuration::EmbeddedRegistryMirror.new
  getter timeouts : Configuration::Timeouts = Configuration::Timeouts.new
  getter include_instance_type_in_instance_name : Bool = false

  def all_kubelet_args
    ["cloud-provider=external", "resolv-conf=/etc/k8s-resolv.conf"] + kubelet_args
  end
end
