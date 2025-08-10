module Configuration
  class Manifests
    include YAML::Serializable
    include YAML::Serializable::Unmapped

    getter cloud_controller_manager_manifest_url : String = "https://github.com/hetznercloud/hcloud-cloud-controller-manager/releases/download/v1.26.0/ccm-networks.yaml"
    getter csi_driver_manifest_url : String = "https://raw.githubusercontent.com/hetznercloud/csi-driver/v2.17.0/deploy/kubernetes/hcloud-csi.yml"
    getter system_upgrade_controller_deployment_manifest_url : String = "https://github.com/rancher/system-upgrade-controller/releases/download/v0.16.0/system-upgrade-controller.yaml"
    getter system_upgrade_controller_crd_manifest_url : String = "https://github.com/rancher/system-upgrade-controller/releases/download/v0.16.0/crd.yaml"
    getter cluster_autoscaler_manifest_url : String = "https://raw.githubusercontent.com/kubernetes/autoscaler/master/cluster-autoscaler/cloudprovider/hetzner/examples/cluster-autoscaler-run-on-master.yaml"
    getter cluster_autoscaler_container_image_tag : String = "v1.33.0"

    def initialize
    end
  end
end
