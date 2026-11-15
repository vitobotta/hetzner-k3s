require "../configuration/loader"
require "../hetzner/client"
require "../hetzner/instance/delete"
require "../util"
require "../util/shell"
require "./node_detection"

# Removes worker nodes that are no longer part of the configuration, so the config file can be the
# source of truth instead of the Maintenance page's manual steps.
#
# Opt-in through `reconcile_node_pools`, and destructive, so it asks before it touches anything:
# outside a TTY, or when --force is given, it does not prompt; --dry-run stops after printing.
# Masters, autoscaler managed nodes and anything the configuration still renders are left alone.
class Cluster::NodePoolReconciler
  include Cluster::NodeDetection
  include Util::Shell

  DRAIN_TIMEOUT = "10m"

  NODE_GROUP_LABEL = "hcloud/node-group"

  # The API paginates, so an unpaged read would quietly under-report on a large cluster and leave
  # nodes behind that the config no longer has.
  PAGE_SIZE = 50

  MAX_PAGES = 40

  getter errors : Array(String) = [] of String

  @instances : Array(NamedTuple(name: String, autoscaled: Bool))?
  @node_names : Array(String)?

  def initialize(
    @configuration : Configuration::Loader,
    @force : Bool = false,
    @dry_run : Bool = false,
    @input : IO = STDIN,
    @interactive : Bool = STDIN.tty?
  )
  end

  # `documented_names` is everything the configuration renders right now, masters included.
  def run(documented_names : Array(String)) : Bool
    return true unless settings.reconcile_node_pools

    candidates = removable_nodes(documented_names)
    return true if candidates.empty?

    log_line "#{candidates.size} node(s) are no longer in the configuration:"
    candidates.each { |name| log_line "  - #{name}" }

    if @dry_run
      log_line "Dry run: nothing removed"
      return true
    end

    unless @force || confirmed?
      log_line "Nothing removed. Re-run with --force to apply, or --dry-run to only list."
      return true
    end

    remove(candidates)
    errors.empty?
  end

  private def remove(candidates : Array(String)) : Nil
    candidates.each do |name|
      log_line "Removing #{name}..."
      drain(name)
      Hetzner::Instance::Delete.new(settings, hetzner_client, name).run if cloud_instance_names.includes?(name)
      delete_node_object(name)
      log_line "...#{name} removed"
    rescue ex : Exception
      errors << "#{name}: #{ex.message}"
      log_line "Failed to remove #{name}: #{ex.message}"
    end
  end

  # Cordon first so nothing new lands there while the drain runs.
  private def drain(name : String) : Nil
    return unless node_names.includes?(name)

    run_kubectl("cordon #{name}", required: true)
    run_kubectl("drain #{name} --ignore-daemonsets --delete-emptydir-data --timeout=#{DRAIN_TIMEOUT}", required: true)
  end

  private def delete_node_object(name : String) : Nil
    return unless node_names.includes?(name)

    run_kubectl("delete node #{name}", required: false)
  end

  private def removable_nodes(documented_names : Array(String)) : Array(String)
    candidates = (cloud_instance_names + node_names).uniq.reject do |name|
      documented_names.includes?(name) ||
        autoscaled_instance_names.includes?(name) ||
        autoscaled_node_name?(name) ||
        node_without_server?(name)
    end

    candidates.sort
  end

  # A node object can outlive its server, and an autoscaled one takes its pool name as a prefix.
  private def autoscaled_node_name?(name : String) : Bool
    settings.worker_node_pools.select(&.autoscaling_enabled).any? do |pool|
      name.starts_with?("#{node_group_name(pool)}-")
    end
  end

  # Nodes with no server of this cluster: the external ones the tool cannot name (a node that does
  # not manage its hostname reports the machine's own hostname), so removing them would break a
  # cluster the configuration still describes. A node that looks like a static cloud worker of this
  # cluster and has no server is one whose server is gone, so it is the exception.
  private def node_without_server?(name : String) : Bool
    !cloud_instance_names.includes?(name) && !static_worker_name?(name)
  end

  private def static_worker_name?(name : String) : Bool
    name.matches?(/\A#{Regex.escape(settings.cluster_name)}(-[a-z\d]+)?-pool-[a-z\d-]+-worker\d+\z/)
  end

  private def run_kubectl(arguments : String, required : Bool) : Nil
    command = "kubectl #{arguments} --request-timeout=30s 2>&1"
    result = run_shell_command(command, configuration.kubeconfig_path, settings.hetzner_token, abort_on_error: false, print_output: false)

    return if result.success?
    return unless required

    raise "kubectl #{arguments.split.first} failed: #{result.output.strip}"
  end

  private def cloud_instance_names : Array(String)
    instances.map { |instance| instance[:name] }
  end

  private def autoscaled_instance_names : Array(String)
    instances.select { |instance| instance[:autoscaled] }.map { |instance| instance[:name] }
  end

  private def instances : Array(NamedTuple(name: String, autoscaled: Bool))
    @instances ||= fetch_instances
  end

  # An empty list would let the run delete servers with no cordon and no drain, so a failed listing
  # stops it instead.
  private def node_names : Array(String)
    @node_names ||= begin
      result = run_shell_command("kubectl get nodes -o=custom-columns=NAME:.metadata.name --no-headers --request-timeout=10s 2>/dev/null", configuration.kubeconfig_path, settings.hetzner_token, abort_on_error: false, print_output: false)
      raise "kubectl get nodes failed: #{result.output.strip}" unless result.success?

      result.output.split("\n").map(&.strip).reject(&.empty?)
    end
  end

  # Servers of the cluster are labelled `cluster=<name>`, but autoscaled ones never carry that label:
  # the autoscaler sets only `hcloud/node-group` on them, which is why NodeDetection and
  # Cluster::Delete query those pools a second time. Without this the autoscaled set is always empty
  # and every autoscaled node looks removable.
  private def fetch_instances : Array(NamedTuple(name: String, autoscaled: Bool))
    flags = {} of String => Bool

    server_names("cluster=#{settings.cluster_name}").each { |name| flags[name] ||= false }

    settings.worker_node_pools.each do |pool|
      next unless pool.autoscaling_enabled

      server_names("hcloud/node-group=#{node_group_name(pool)}").each { |name| flags[name] = true }
    end

    flags.map { |name, autoscaled| {name: name, autoscaled: autoscaled} }
  end

  private def server_names(label_selector : String) : Array(String)
    names = [] of String
    page = 1

    MAX_PAGES.times do
      success, response = hetzner_client.get("/servers", {:label_selector => label_selector, :page => page.to_s, :per_page => PAGE_SIZE.to_s})
      raise "Failed to list servers (#{label_selector}): #{response}" unless success

      body = JSON.parse(response)
      body["servers"].as_a.each { |server| names << server["name"].as_s }

      next_page = body["meta"]?.try(&.["pagination"]?).try(&.["next_page"]?).try(&.as_i64?)
      break unless next_page

      page = next_page.to_i
    end

    names
  end

  private def node_group_name(pool : Configuration::Models::WorkerNodePool) : String
    pool.include_cluster_name_as_prefix ? "#{settings.cluster_name}-#{pool.name}" : pool.name.to_s
  end

  private def confirmed? : Bool
    unless @interactive
      log_line "No terminal to confirm, so nothing was removed"
      return false
    end

    print "Drain and delete them? [y/N]: "
    answer = @input.gets.try(&.strip.downcase)
    answer == "y" || answer == "yes"
  end

  private def default_log_prefix
    "Node pools"
  end
end
