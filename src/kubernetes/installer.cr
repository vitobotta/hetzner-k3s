require "crinja"
require "base64"
require "file_utils"

require "../util"
require "../util/ssh"
require "../util/shell"
require "../kubernetes/util"
require "../hetzner/instance"
require "../hetzner/load_balancer"
require "../configuration/loader"
require "./software/system_upgrade_controller"
require "./software/cilium"
require "./software/hetzner/secret"
require "./software/hetzner/cloud_controller_manager"
require "./software/hetzner/csi_driver"
require "./software/cluster_autoscaler"
require "./software/installer"
require "./control_plane/setup"
require "./worker/setup"
require "./kubeconfig_manager"
require "./script/master_generator"
require "./script/worker_generator"

class Kubernetes::Installer
  include Util
  include Util::Shell

  getter configuration : Configuration::Loader
  getter settings : Configuration::Main { configuration.settings }
  getter autoscaling_worker_node_pools : Array(Configuration::Models::WorkerNodePool)
  getter load_balancer : Hetzner::LoadBalancer?
  getter ssh : ::Util::SSH
  getter kubeconfig_manager : Kubernetes::KubeconfigManager
  getter master_generator : Kubernetes::Script::MasterGenerator
  getter worker_generator : Kubernetes::Script::WorkerGenerator

  private getter software_installer : Kubernetes::Software::Installer
  private getter control_plane_setup : Kubernetes::ControlPlane::Setup
  private getter worker_setup : Kubernetes::Worker::Setup

  def initialize(
    @configuration,
    @load_balancer,
    @ssh,
    @autoscaling_worker_node_pools
  )
    @kubeconfig_manager = Kubernetes::KubeconfigManager.new(@configuration, settings, @ssh)
    @master_generator = Kubernetes::Script::MasterGenerator.new(@configuration, settings)
    @worker_generator = Kubernetes::Script::WorkerGenerator.new(@configuration, settings)
    @software_installer = Kubernetes::Software::Installer.new(@configuration, settings)
    @control_plane_setup = Kubernetes::ControlPlane::Setup.new(@configuration, settings, @ssh, @master_generator, @kubeconfig_manager)
    @worker_setup = Kubernetes::Worker::Setup.new(@configuration, settings, @ssh, @worker_generator)
  end

  # Store masters and first_master for use in other methods
  private getter masters : Array(Hetzner::Instance) = [] of Hetzner::Instance
  private getter first_master_instance : Hetzner::Instance?

  def run(masters_installation_queue_channel, workers_installation_queue_channel, completed_channel, master_count, worker_count)
    ensure_kubectl_is_installed!

    # Set up control plane
    @masters, @first_master_instance = @control_plane_setup.set_up_control_plane(masters_installation_queue_channel, master_count, load_balancer)

    # Install all software components
    @software_installer.install_all(@first_master_instance, @masters, ssh, autoscaling_worker_node_pools)

    # Set up workers if any
    if worker_count > 0
      workers = @worker_setup.set_up_workers(workers_installation_queue_channel, worker_count, @masters, @first_master_instance)
    end

    switch_to_context(default_context)

    completed_channel.send(nil)
  end

  private def default_context
    load_balancer.nil? ? first_master.name : settings.cluster_name
  end

  private def first_master : Hetzner::Instance
    @first_master_instance.not_nil!
  end

  private def default_log_prefix
    "Kubernetes Installer"
  end
end
