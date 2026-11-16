require "../../configuration/loader"
require "../../configuration/main"
require "../../hetzner/client"
require "../../hetzner/instance"
require "../../hetzner/instances_list"
require "../../util"
require "../../util/ssh"
require "../deployment_helper"
require "../local_firewall/setup"
require "../script/worker_generator"

# `create` only ever provisions the pools that are not autoscaling, so an autoscaled node keeps the
# configuration it was born with. With `synchronise_autoscaled_nodes: true` the nodes the autoscaler
# owns are brought up to date the same way static workers are. The worker script itself only stops
# and restarts k3s-agent when something k3s reads at startup actually changed, so an unchanged node
# is written to without being interrupted.
class Kubernetes::Worker::AutoscaledSynchroniser
  include Util
  include Kubernetes::SSHDeploymentHelper

  # Enough to keep a large pool moving without restarting a whole fleet at once.
  CONCURRENCY = 5

  # One `kubectl get nodes` for the whole run: a node that is not Ready yet, or that the autoscaler
  # has cordoned for a scale down, is left alone.
  NODE_STATE_COLUMNS = %{custom-columns=NAME:.metadata.name,READY:.status.conditions[?(@.type=="Ready")].status,UNSCHEDULABLE:.spec.unschedulable}

  getter settings : Configuration::Main
  getter ssh : ::Util::SSH

  private getter configuration : Configuration::Loader
  private getter hetzner_client : Hetzner::Client
  private getter worker_generator : Kubernetes::Script::WorkerGenerator
  private getter local_firewall_setup : Kubernetes::LocalFirewall::Setup

  def initialize(
    @configuration : Configuration::Loader,
    @settings : Configuration::Main,
    @ssh : ::Util::SSH,
    @worker_generator : Kubernetes::Script::WorkerGenerator,
    @hetzner_client : Hetzner::Client
  )
    @local_firewall_setup = Kubernetes::LocalFirewall::Setup.new(settings, ssh)
  end

  def run(masters : Array(Hetzner::Instance), first_master : Hetzner::Instance?) : NamedTuple(updated: Int32, skipped: Int32, failed: Int32)
    counters = {updated: 0, skipped: 0, failed: 0}
    pools = settings.worker_node_pools.select(&.autoscaling_enabled)
    return counters if pools.empty? || first_master.nil?

    first_master_instance = first_master.not_nil!
    states = node_states(first_master_instance)
    mutex = Mutex.new
    semaphore = Channel(Nil).new(CONCURRENCY)
    done = Channel(Nil).new
    pending = 0

    pools.each do |pool|
      instances = find_instances(pool)
      next if instances.empty?

      candidates = instances.select do |instance|
        state = states[instance.name]?
        state && state[:ready] && !state[:unschedulable]
      end

      skipped = instances.size - candidates.size
      mutex.synchronize { counters = {updated: counters[:updated], skipped: counters[:skipped] + skipped, failed: counters[:failed]} }
      next if candidates.empty?

      log_line "Synchronising #{candidates.size} node(s) of autoscaled pool #{pool.name}"
      script = worker_generator.generate_script(masters, first_master_instance, pool)

      candidates.each do |instance|
        pending += 1
        semaphore.send(nil)
        spawn do
          begin
            update(instance, script)
            mutex.synchronize { counters = {updated: counters[:updated] + 1, skipped: counters[:skipped], failed: counters[:failed]} }
          rescue ex : Exception
            # A node the autoscaler picked for a scale down can disappear mid-run, so a failure is
            # recorded and never aborts the run.
            log_line "#{instance.name}: #{ex.message}"
            mutex.synchronize { counters = {updated: counters[:updated], skipped: counters[:skipped], failed: counters[:failed] + 1} }
          ensure
            # The wait below counts completions, so a raised fiber must still report one.
            semaphore.receive
            done.send(nil)
          end
        end
      end
    end

    pending.times { done.receive }

    counters
  end

  private def update(instance : Hetzner::Instance, script : String) : Nil
    local_firewall_setup.deploy(instance)
    deploy_to_instance(instance, script)
  end

  private def node_states(first_master : Hetzner::Instance) : Hash(String, NamedTuple(ready: Bool, unschedulable: Bool))
    command = "KUBECONFIG=/etc/rancher/k3s/k3s.yaml kubectl get nodes -o='#{NODE_STATE_COLUMNS}' --no-headers 2>/dev/null"
    output = ssh.run(first_master, settings.networking.ssh.port, command, settings.networking.ssh.use_agent, print_output: false)

    states = {} of String => NamedTuple(ready: Bool, unschedulable: Bool)

    output.lines.each do |line|
      columns = line.split
      next if columns.size < 2

      states[columns[0]] = {ready: columns[1] == "True", unschedulable: columns[2]? == "true"}
    end

    states
  end

  # Autoscaler-created servers carry their node group as a label, which makes them findable without
  # parsing generated instance names.
  private def find_instances(pool : Configuration::Models::WorkerNodePool) : Array(Hetzner::Instance)
    success, response = hetzner_client.get("/servers", {:label_selector => "hcloud/node-group=#{node_group_name(pool)}"})
    return [] of Hetzner::Instance unless success

    Hetzner::InstancesList.from_json(response).servers.reject { |instance| instance.status == "deleting" }
  end

  private def node_group_name(pool) : String
    pool.include_cluster_name_as_prefix ? "#{settings.cluster_name}-#{pool.name}" : pool.name.to_s
  end

  private def default_log_prefix
    "Autoscaled nodes"
  end
end
