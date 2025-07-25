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
require "./kubeconfig_manager"
require "./script/master_generator"
require "./script/worker_generator"

class Kubernetes::Installer
  include Util
  include Util::Shell

  CLOUD_INIT_WAIT_SCRIPT = {{ read_file("#{__DIR__}/../../templates/cloud_init_wait_script.sh") }}

  getter configuration : Configuration::Loader
  getter settings : Configuration::Main { configuration.settings }
  getter masters : Array(Hetzner::Instance) = [] of Hetzner::Instance
  getter workers : Array(Hetzner::Instance) = [] of Hetzner::Instance
  getter autoscaling_worker_node_pools : Array(Configuration::WorkerNodePool)
  getter load_balancer : Hetzner::LoadBalancer?
  getter ssh : ::Util::SSH
  getter kubeconfig_manager : Kubernetes::KubeconfigManager
  getter master_generator : Kubernetes::Script::MasterGenerator
  getter worker_generator : Kubernetes::Script::WorkerGenerator

  private getter first_master : Hetzner::Instance?
  private getter cni : Configuration::NetworkingComponents::CNI { settings.networking.cni }

  def initialize(
      @configuration,
      @load_balancer,
      @ssh,
      @autoscaling_worker_node_pools
    )
    @kubeconfig_manager = Kubernetes::KubeconfigManager.new(@configuration, settings, @ssh)
    @master_generator = Kubernetes::Script::MasterGenerator.new(@configuration, settings)
    @worker_generator = Kubernetes::Script::WorkerGenerator.new(@configuration, settings)
  end

  def run(masters_installation_queue_channel, workers_installation_queue_channel, completed_channel, master_count, worker_count)
    ensure_kubectl_is_installed!

    set_up_control_plane(masters_installation_queue_channel, master_count)

    # Save kubeconfig using the new manager
    kubeconfig_manager.save_kubeconfig(masters, first_master, load_balancer)

    Kubernetes::Software::Cilium.new(configuration, settings).install if settings.networking.cni.enabled? && settings.networking.cni.cilium?

    Kubernetes::Software::Hetzner::Secret.new(configuration, settings).create
    Kubernetes::Software::Hetzner::CloudControllerManager.new(configuration, settings).install
    Kubernetes::Software::Hetzner::CSIDriver.new(configuration, settings).install

    Kubernetes::Software::SystemUpgradeController.new(configuration, settings).install

    if worker_count > 0
      set_up_workers(workers_installation_queue_channel, worker_count, master_count)
    end

    Kubernetes::Software::ClusterAutoscaler.new(configuration, settings, masters, first_master, ssh, autoscaling_worker_node_pools).install

    switch_to_context(default_context)

    completed_channel.send(nil)
  end

  private def set_up_control_plane(masters_installation_queue_channel, master_count)
    master_count.times { masters << masters_installation_queue_channel.receive }
    masters_ready_channel = Channel(Hetzner::Instance).new

    set_up_first_master(master_count)

    (masters - [first_master]).each do |master|
      spawn do
        deploy_k3s_to_master(master, master_count)
        masters_ready_channel.send(master)
      end
    end

    (master_count - 1).times { masters_ready_channel.receive }
  end

  private def set_up_workers(workers_installation_queue_channel, worker_count, master_count)
    workers_ready_channel = Channel(Hetzner::Instance).new
    semaphore = Channel(Nil).new(10)
    mutex = Mutex.new

    worker_count.times do
      semaphore.send(nil)
      spawn do
        worker = workers_installation_queue_channel.receive
        mutex.synchronize { workers << worker }

        pool = settings.worker_node_pools.find do |pool|
          worker.name.split("-")[0..-2].join("-") =~ /^#{settings.cluster_name.to_s}-.*pool-#{pool.name.to_s}$/
        end

        deploy_k3s_to_worker(pool, worker)

        semaphore.receive
        workers_ready_channel.send(worker)
      end
    end

    worker_count.times { workers_ready_channel.receive }

    wait_for_one_worker_to_be_ready
  end

  private def wait_for_one_worker_to_be_ready
    log_line "Waiting for at least one worker node to be ready...", log_prefix: "Cluster Autoscaler"

    timeout = Time.monotonic + 5.minutes

    loop do
      output = ssh.run(first_master, settings.networking.ssh.port, "KUBECONFIG=/etc/rancher/k3s/k3s.yaml kubectl get nodes", settings.networking.ssh.use_agent, print_output: false)

      ready_workers = output.lines.count { |line| line.includes?("worker") && line.includes?("Ready") }

      break if ready_workers > 0

      if Time.monotonic > timeout
        log_line "Timeout waiting for worker nodes, aborting" , log_prefix: "Cluster Autoscaler"
        exit 1
      end

      sleep 5.seconds
    end
  end

  private def set_up_first_master(master_count : Int)
    wait_for_cloud_init(first_master)
    install_script = master_generator.generate_script(first_master, masters, first_master, load_balancer, kubeconfig_manager)
    output = deploy_to_instance(first_master, install_script)

    log_line "Waiting for the control plane to be ready...", log_prefix: "Instance #{first_master.name}"
    sleep 10.seconds unless /No change detected/ =~ output

    kubeconfig_manager.save_kubeconfig(masters, first_master, load_balancer)
    sleep 5.seconds

    wait_for_control_plane
    log_line "...k3s deployed", log_prefix: "Instance #{first_master.name}"
  end

  private def deploy_k3s_to_master(master : Hetzner::Instance, master_count)
    deploy_to_master(master)
  end

  private def deploy_k3s_to_worker(pool, worker : Hetzner::Instance)
    deploy_to_worker(worker, pool)
  end

  private def deploy_to_master(instance : Hetzner::Instance)
    wait_for_cloud_init(instance)
    script = master_generator.generate_script(instance, masters, first_master, load_balancer, kubeconfig_manager)
    deploy_to_instance(instance, script)
    log_line "...k3s deployed", log_prefix: "Instance #{instance.name}"
  end

  private def deploy_to_worker(instance : Hetzner::Instance, pool)
    wait_for_cloud_init(instance)
    script = worker_generator.generate_script(masters, first_master, pool)
    deploy_to_instance(instance, script)
    log_line "...k3s deployed", log_prefix: "Instance #{instance.name}"
  end

  private def wait_for_cloud_init(instance : Hetzner::Instance)
    ssh.run(instance, settings.networking.ssh.port, CLOUD_INIT_WAIT_SCRIPT, settings.networking.ssh.use_agent)
  end

  private def deploy_to_instance(instance : Hetzner::Instance, script : String) : String
    ssh.run(instance, settings.networking.ssh.port, script, settings.networking.ssh.use_agent)
  end

  private def wait_for_control_plane
    command = "kubectl cluster-info 2> /dev/null"
    Retriable.retry(max_attempts: 3, on: Tasker::Timeout, backoff: false) do
      Tasker.timeout(30.seconds) do
        loop do
          result = run_shell_command(command, configuration.kubeconfig_path, settings.hetzner_token, log_prefix: "Control plane", abort_on_error: false, print_output: false)
          break if result.output.includes?("running")
          sleep 1.seconds
        end
      end
    end
  end

  private def first_master : Hetzner::Instance
    @first_master ||= begin
      token = K3s.k3s_token(settings, masters)
      return masters[0] if token.empty?

      bootstrapped_master = masters.sort_by(&.name).find { |master| K3s.k3s_token(settings, [master]) == token }
      bootstrapped_master || masters[0]
    end
  end

  private def default_log_prefix
    "Kubernetes software"
  end

  private def default_context
    load_balancer.nil? ? first_master.name : settings.cluster_name
  end
end
