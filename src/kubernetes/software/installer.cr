require "../../configuration/loader"
require "../../configuration/main"
require "../../configuration/models/worker_node_pool"
require "../../hetzner/instance"
require "../../util/ssh"
require "../installer"
require "./cilium"
require "./hetzner/secret"
require "./hetzner/cloud_controller_manager"
require "./hetzner/csi_driver"
require "./system_upgrade_controller"
require "./cluster_autoscaler"

class Kubernetes::Software::Installer
  def initialize(@configuration : Configuration::Loader, @settings : Configuration::Main)
  end

  def install_all(first_master, masters, ssh, autoscaling_worker_node_pools)
    install_cni_if_needed
    create_hetzner_secret
    install_hetzner_cloud_controller_manager_if_enabled
    install_hetzner_csi_driver_if_enabled
    install_system_upgrade_controller
    install_cluster_autoscaler_if_enabled(first_master, masters, ssh, autoscaling_worker_node_pools)
  end

  private def install_cni_if_needed
    Kubernetes::Software::Cilium.new(@configuration, @settings).install if @settings.networking.cni.enabled? && @settings.networking.cni.cilium?
  end

  private def create_hetzner_secret
    Kubernetes::Software::Hetzner::Secret.new(@configuration, @settings).create
  end

  private def install_hetzner_cloud_controller_manager_if_enabled
    Kubernetes::Software::Hetzner::CloudControllerManager.new(@configuration, @settings).install if @settings.addons.cloud_controller_manager.enabled?
  end

  private def install_hetzner_csi_driver_if_enabled
    Kubernetes::Software::Hetzner::CSIDriver.new(@configuration, @settings).install if @settings.addons.csi_driver.enabled?
  end

  private def install_system_upgrade_controller
    Kubernetes::Software::SystemUpgradeController.new(@configuration, @settings).install
  end

  private def install_cluster_autoscaler_if_enabled(first_master, masters, ssh, autoscaling_worker_node_pools)
    if @settings.addons.cluster_autoscaler.enabled? && first_master
      Kubernetes::Software::ClusterAutoscaler.new(@configuration, @settings, masters, first_master, ssh, autoscaling_worker_node_pools).install
    end
  end
end

