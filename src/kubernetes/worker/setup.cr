require "../../configuration/loader"
require "../../configuration/main"
require "../../hetzner/instance"
require "../../util/ssh"
require "../deployment_helper"
require "../script/worker_generator"

class Kubernetes::Worker::Setup
  include Kubernetes::SSHDeploymentHelper

  getter settings : Configuration::Main
  getter ssh : ::Util::SSH

  def initialize(
    @configuration : Configuration::Loader,
    @settings : Configuration::Main,
    @ssh : ::Util::SSH,
    @worker_generator : Kubernetes::Script::WorkerGenerator
  )
  end

  def set_up_workers(workers_installation_queue_channel, worker_count, masters, first_master)
    # Assert that first_master is not nil (it should always be present at this point)
    first_master_instance = first_master.not_nil!
    workers = [] of Hetzner::Instance
    workers_ready_channel = Channel(Hetzner::Instance).new
    semaphore = Channel(Nil).new(10)
    mutex = Mutex.new

    worker_count.times do
      semaphore.send(nil)
      spawn do
        worker = workers_installation_queue_channel.receive
        mutex.synchronize { workers << worker }

        pool = @settings.worker_node_pools.find do |pool|
          worker.name.split("-")[0..-2].join("-") =~ /^#{@settings.cluster_name.to_s}-.*pool-#{pool.name.to_s}$/
        end

        deploy_to_worker(worker, pool, masters, first_master_instance)

        semaphore.receive
        workers_ready_channel.send(worker)
      end
    end

    worker_count.times { workers_ready_channel.receive }

    wait_for_one_worker_to_be_ready(first_master_instance)

    workers
  end

  private def deploy_to_worker(instance : Hetzner::Instance, pool, masters, first_master)
    wait_for_cloud_init(instance)
    script = @worker_generator.generate_script(masters, first_master, pool)
    deploy_to_instance(instance, script)
  end

  private def wait_for_one_worker_to_be_ready(first_master : Hetzner::Instance)
    log_line "Waiting for at least one worker node to be ready...", log_prefix: "Cluster Autoscaler"

    timeout = Time.monotonic + 5.minutes

    loop do
      output = @ssh.run(first_master, @settings.networking.ssh.port, "KUBECONFIG=/etc/rancher/k3s/k3s.yaml kubectl get nodes", @settings.networking.ssh.use_agent, print_output: false)

      ready_workers = output.lines.count { |line| line.includes?("worker") && line.includes?("Ready") }

      break if ready_workers > 0

      if Time.monotonic > timeout
        log_line "Timeout waiting for worker nodes, aborting", log_prefix: "Cluster Autoscaler"
        exit 1
      end

      sleep 5.seconds
    end
  end

  private def default_log_prefix
    "Worker Setup"
  end

  private def log_line(message, log_prefix = default_log_prefix)
    puts "[#{log_prefix}] #{message}"
  end
end

