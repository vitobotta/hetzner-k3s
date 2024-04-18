require "yaml"

require "./node_pool"
require "./datastore"

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
  getter image : String = "ubuntu-22.04"
  getter autoscaling_image : String?
  getter snapshot_os : String = "default"
  getter networking : Configuration::Networking = Configuration::Networking.new
  getter cloud_controller_manager_manifest_url : String = "https://github.com/hetznercloud/hcloud-cloud-controller-manager/releases/download/v1.19.0/ccm-networks.yaml"
  getter csi_driver_manifest_url : String = "https://raw.githubusercontent.com/hetznercloud/csi-driver/v2.6.0/deploy/kubernetes/hcloud-csi.yml"
  getter system_upgrade_controller_deployment_manifest_url : String = "https://github.com/rancher/system-upgrade-controller/releases/download/v0.13.4/system-upgrade-controller.yaml"
  getter system_upgrade_controller_crd_manifest_url : String = "https://github.com/rancher/system-upgrade-controller/releases/download/v0.13.4/crd.yaml"
  getter cluster_autoscaler_manifest_url : String = "https://raw.githubusercontent.com/kubernetes/autoscaler/master/cluster-autoscaler/cloudprovider/hetzner/examples/cluster-autoscaler-run-on-master.yaml"
  getter datastore : Configuration::Datastore = Configuration::Datastore.new

  def all_kubelet_args
    ["cloud-provider=external", "resolv-conf=/etc/k8s-resolv.conf"] + kubelet_args
  end
end
