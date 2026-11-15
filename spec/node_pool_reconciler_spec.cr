require "./routing_spec_helper"
require "../src/cluster/node_pool_reconciler"

# Serves a paged `/servers` listing, honours the name filter that Instance::Find uses, and records
# the deletions.
private class FakeNodesClient < Hetzner::Client
  getter pages = [] of String
  getter deleted_ids = [] of Int32
  property servers = [] of Array(Tuple(String, Bool))

  def initialize
    super("fake-token")
  end

  def get(path, params : Hash = {} of Symbol => String | Bool | Nil)
    if name = params[:name]?
      matches = all.reject { |entry| entry[:name] != name.to_s }
      return {true, listing(matches)}
    end

    # The API filters on the selector. The `cluster=` listing never returns autoscaled servers: the
    # autoscaler labels them with the node group only.
    page = (params[:page] || "1").to_s.to_i
    @pages << page.to_s

    if selector = params[:label_selector]?
      node_group_query = selector.to_s.starts_with?("hcloud/node-group=")
      matches = all.select { |entry| entry[:autoscaled] == node_group_query && entry[:page] == page }
      return {true, listing(matches, page + 1)}
    end

    {true, listing(all.select { |entry| entry[:page] == page }, page + 1)}
  end

  def delete(path, id)
    @deleted_ids << id.to_s.to_i
    {true, ""}
  end

  private def all : Array(NamedTuple(id: Int32, name: String, autoscaled: Bool, page: Int32))
    entries = [] of NamedTuple(id: Int32, name: String, autoscaled: Bool, page: Int32)
    next_id = 100

    servers.each_with_index do |page, index|
      page.each do |name, autoscaled|
        entries << {id: next_id, name: name, autoscaled: autoscaled, page: index + 1}
        next_id += 1
      end
    end

    entries
  end

  private def listing(entries, next_page : Int32? = nil) : String
    servers = entries.map do |entry|
      labels = entry[:autoscaled] ? %({"hcloud/node-group": "pool"}) : "{}"
      %({"id": #{entry[:id]}, "name": "#{entry[:name]}", "status": "running", "labels": #{labels}})
    end

    meta = next_page && entries.any? ? %(, "meta": {"pagination": {"next_page": #{next_page}}}) : ""
    %({"servers": [#{servers.join(", ")}]#{meta}})
  end
end

private class FakeNodesSSH
  property nodes = [] of String
  property failing = [] of String
  property nodes_fail = false
  getter calls = [] of String

  def kubectl(command : String) : Util::Shell::CommandResult
    @calls << command

    if command.starts_with?("kubectl get nodes")
      return Util::Shell::CommandResult.new("", 1) if nodes_fail

      return Util::Shell::CommandResult.new(nodes.join("\n"), 0)
    end

    failing.each do |failure|
      return Util::Shell::CommandResult.new("error: #{failure}", 1) if command.includes?(failure)
    end

    Util::Shell::CommandResult.new("", 0)
  end
end

private class ReconcilerProbe < Cluster::NodePoolReconciler
  getter ssh = FakeNodesSSH.new
  getter client = FakeNodesClient.new

  def initialize(loader, force = true, dry_run = false, input : IO = IO::Memory.new(""), interactive = false)
    super(loader, force, dry_run, input, interactive)
  end

  def hetzner_client : Hetzner::Client
    client
  end

  def run_shell_command(command : String, kubeconfig_path : String, hetzner_token : String, error_message : String = "", abort_on_error : Bool = true, log_prefix : String = "", print_output : Bool = true) : Util::Shell::CommandResult
    ssh.kubectl(command)
  end
end

private def reconciler_config : String
  RoutingSpec.config(false).split("worker_node_pools:").first.not_nil! + <<-YAML
reconcile_node_pools: true
worker_node_pools:
- name: pool
  instance_type: cpx22
  instance_count: 1
  location: nbg1
- name: auto
  instance_type: cpx22
  instance_count: 0
  autoscaling:
    enabled: true
    min_instances: 0
    max_instances: 3
- name: db
  instance_type: external
  instance_count: 1
  external:
    provider: generic
    nodes:
    - host: 10.10.0.90
      ssh_user: operator
      ssh_port: 2222
      ssh_private_key_path: /nonexistent/test-key
      manage_hostname: true
      index: 1
YAML
end

private def with_reconciler(yaml : String, force = true, dry_run = false, input : IO = IO::Memory.new(""), interactive = false, &)
  RoutingSpec.with_loader(yaml) do |loader|
    yield ReconcilerProbe.new(loader, force, dry_run, input, interactive), loader
  end
end

describe "node pool reconciliation" do
  it "does nothing when the flag is off" do
    with_reconciler(RoutingSpec.config(false)) do |probe|
      probe.run(["routing-test-worker1"]).should be_true
      probe.client.pages.should be_empty
    end
  end

  it "removes a node the configuration no longer has" do
    with_reconciler(reconciler_config) do |probe|
      probe.client.servers = [[{"routing-test-worker1", false}, {"routing-test-gone", false}]]
      probe.ssh.nodes = ["routing-test-worker1", "routing-test-gone"]

      probe.run(["routing-test-worker1"]).should be_true

      probe.ssh.calls.should contain("kubectl cordon routing-test-gone --request-timeout=30s 2>&1")
      probe.ssh.calls.any?(&.starts_with?("kubectl drain routing-test-gone --ignore-daemonsets")).should be_true
      probe.client.deleted_ids.size.should eq(1)
    end
  end

  it "cordon before drain so nothing lands on the node being removed" do
    with_reconciler(reconciler_config) do |probe|
      probe.client.servers = [[{"routing-test-gone", false}]]
      probe.ssh.nodes = ["routing-test-gone"]

      probe.run([] of String)

      probe.ssh.calls.index { |call| call.starts_with?("kubectl cordon") }.not_nil!.should be < probe.ssh.calls.index { |call| call.starts_with?("kubectl drain") }.not_nil!
    end
  end

  # The name is shaped like a static worker's and the server is absent from the `cluster=` listing,
  # so only the `hcloud/node-group` lookup can keep it.
  it "leaves autoscaler managed nodes alone" do
    with_reconciler(reconciler_config) do |probe|
      probe.client.servers = [[{"routing-test-pool-auto-worker1", true}]]
      probe.ssh.nodes = ["routing-test-pool-auto-worker1"]

      probe.run([] of String)

      probe.ssh.calls.any?(&.starts_with?("kubectl drain")).should be_false
    end
  end

  it "leaves masters alone" do
    with_reconciler(reconciler_config) do |probe|
      probe.client.servers = [[{"routing-test-master1", false}]]
      probe.ssh.nodes = ["routing-test-master1"]

      probe.run(["routing-test-master1"])

      probe.ssh.calls.any?(&.starts_with?("kubectl drain")).should be_false
    end
  end

  it "reads every page of the listing" do
    with_reconciler(reconciler_config) do |probe|
      probe.client.servers = [[{"routing-test-worker1", false}], [{"routing-test-gone", false}]]
      probe.ssh.nodes = ["routing-test-worker1", "routing-test-gone"]

      probe.run(["routing-test-worker1"])

      probe.client.pages.should contain("1")
      probe.client.pages.should contain("2")
      probe.ssh.calls.any?(&.starts_with?("kubectl drain routing-test-gone")).should be_true
    end
  end

  it "removes a node object whose server is already gone" do
    with_reconciler(reconciler_config) do |probe|
      probe.client.servers = [[] of Tuple(String, Bool)]
      probe.ssh.nodes = ["routing-test-pool-gone-worker1"]

      probe.run([] of String)

      probe.ssh.calls.should contain("kubectl cordon routing-test-pool-gone-worker1 --request-timeout=30s 2>&1")
      probe.ssh.calls.should contain("kubectl delete node routing-test-pool-gone-worker1 --request-timeout=30s 2>&1")
      probe.client.deleted_ids.should be_empty
    end
  end

  # An external node with a managed hostname has the name shape of a cloud worker and no server, so
  # only the configured name keeps it. `create` does not pass external names, the reconciler owns it.
  it "leaves a configured external node with a managed hostname alone" do
    with_reconciler(reconciler_config) do |probe|
      probe.client.servers = [[] of Tuple(String, Bool)]
      probe.ssh.nodes = ["routing-test-pool-db-worker1"]

      probe.run([] of String)

      probe.ssh.calls.any?(&.starts_with?("kubectl drain")).should be_false
    end
  end

  # An external node that does not manage its hostname reports the machine's own hostname, so it
  # cannot be recognized by name and has no server either.
  # An empty list would let it delete servers with no cordon and no drain.
  it "removes nothing when the cluster cannot be listed" do
    with_reconciler(reconciler_config) do |probe|
      probe.client.servers = [[{"routing-test-pool-gone-worker1", false}]]
      probe.ssh.nodes_fail = true

      expect_raises(Exception, "kubectl get nodes failed") { probe.run([] of String) }

      probe.client.deleted_ids.should be_empty
    end
  end

  it "leaves a node that has no server and is not named like a cloud worker alone" do
    with_reconciler(reconciler_config) do |probe|
      probe.client.servers = [[] of Tuple(String, Bool)]
      probe.ssh.nodes = ["dedicated-42.example.net"]

      probe.run([] of String)

      probe.ssh.calls.any?(&.starts_with?("kubectl drain")).should be_false
    end
  end

  # The autoscaler labels servers with the node group, and a node object can outlive its server.
  it "leaves an autoscaled node object alone after its server is gone" do
    with_reconciler(reconciler_config) do |probe|
      probe.client.servers = [[] of Tuple(String, Bool)]
      probe.ssh.nodes = ["auto-abc123"]

      probe.run([] of String)

      probe.ssh.calls.any?(&.starts_with?("kubectl drain")).should be_false
    end
  end

  it "only lists what it would remove on a dry run" do
    with_reconciler(reconciler_config, dry_run: true) do |probe|
      probe.client.servers = [[{"routing-test-gone", false}]]
      probe.ssh.nodes = ["routing-test-gone"]

      probe.run([] of String).should be_true

      probe.ssh.calls.any?(&.starts_with?("kubectl drain")).should be_false
      probe.ssh.calls.any?(&.starts_with?("kubectl cordon")).should be_false
      probe.client.deleted_ids.should be_empty
    end
  end

  it "removes nothing when the answer is no" do
    with_reconciler(reconciler_config, force: false, input: IO::Memory.new("n\n"), interactive: true) do |probe|
      probe.client.servers = [[{"routing-test-gone", false}]]
      probe.ssh.nodes = ["routing-test-gone"]

      probe.run([] of String).should be_true

      probe.ssh.calls.any?(&.starts_with?("kubectl drain")).should be_false
    end
  end

  it "removes them when the answer is yes" do
    with_reconciler(reconciler_config, force: false, input: IO::Memory.new("y\n"), interactive: true) do |probe|
      probe.client.servers = [[{"routing-test-gone", false}]]
      probe.ssh.nodes = ["routing-test-gone"]

      probe.run([] of String).should be_true

      probe.ssh.calls.any?(&.starts_with?("kubectl drain")).should be_true
    end
  end

  it "does not remove anything without a confirmation" do
    with_reconciler(reconciler_config, force: false) do |probe|
      probe.client.servers = [[{"routing-test-gone", false}]]
      probe.ssh.nodes = ["routing-test-gone"]

      probe.run([] of String).should be_true

      probe.ssh.calls.any?(&.starts_with?("kubectl drain")).should be_false
      probe.client.deleted_ids.should be_empty
    end
  end

  it "keeps going and reports the node that failed to drain" do
    with_reconciler(reconciler_config) do |probe|
      probe.client.servers = [[{"routing-test-gone", false}, {"routing-test-stuck", false}]]
      probe.ssh.nodes = ["routing-test-gone", "routing-test-stuck"]
      probe.ssh.failing = ["drain routing-test-stuck"]

      probe.run([] of String).should be_false

      probe.errors.size.should eq(1)
      probe.errors.first.should contain("routing-test-stuck")
      # only the node that drained loses its instance, the stuck one keeps its object for a re-run
      probe.client.deleted_ids.size.should eq(1)
      probe.ssh.calls.should contain("kubectl delete node routing-test-gone --request-timeout=30s 2>&1")
      probe.ssh.calls.should_not contain("kubectl delete node routing-test-stuck --request-timeout=30s 2>&1")
    end
  end
end
