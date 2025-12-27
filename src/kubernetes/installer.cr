require "crinja"
require "../configuration/loader"
require "../hetzner/load_balancer"
require "../util"
require "../util/shell"
require "../util/ssh"
require "./control_plane/setup"
require "./kubeconfig_manager"
require "./local_firewall/setup"
require "./script/master_generator"
require "./script/worker_generator"
require "./software/cilium"
require "./software/cluster_autoscaler"
require "./software/hetzner/cloud_controller_manager"
require "./software/hetzner/csi_driver"
require "./software/hetzner/secret"
require "./software/installer"
require "./software/system_upgrade_controller"
require "./worker/setup"

class Kubernetes::Installer
  include Util
  include Util::Shell

  private getter configuration : Configuration::Loader
  private getter settings : Configuration::Main { configuration.settings }
  private getter autoscaling_worker_node_pools : Array(Configuration::Models::WorkerNodePool)
  private getter load_balancer : Hetzner::LoadBalancer?
  private getter ssh : ::Util::SSH
  private getter kubeconfig_manager : Kubernetes::KubeconfigManager
  private getter master_generator : Kubernetes::Script::MasterGenerator
  private getter worker_generator : Kubernetes::Script::WorkerGenerator

  private getter software_installer : Kubernetes::Software::Installer
  private getter control_plane_setup : Kubernetes::ControlPlane::Setup
  private getter worker_setup : Kubernetes::Worker::Setup
  private getter local_firewall_setup : Kubernetes::LocalFirewall::Setup

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
    @local_firewall_setup = Kubernetes::LocalFirewall::Setup.new(settings, @ssh)
  end

  private getter masters : Array(Hetzner::Instance) = [] of Hetzner::Instance
  private getter first_master_instance : Hetzner::Instance?

  def run(masters_installation_queue_channel, workers_installation_queue_channel, completed_channel, master_count, worker_count)
    ensure_kubectl_is_installed!

    @masters, @first_master_instance = @control_plane_setup.set_up_control_plane(masters_installation_queue_channel, master_count, load_balancer)

    @local_firewall_setup.deploy_to_all_nodes(first_master, @masters)

    @software_installer.install_all(@first_master_instance, @masters, ssh, autoscaling_worker_node_pools)

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
