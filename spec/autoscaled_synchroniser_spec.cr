require "./routing_spec_helper"
require "../src/kubernetes/worker/autoscaled_synchroniser"

private class FakeHetznerClient < Hetzner::Client
  getter selectors = [] of String
  property servers = ""

  def initialize
    super("fake-token")
  end

  # Only server listing happens here.
  def get(path, params : Hash = {} of Symbol => String | Bool | Nil)
    @selectors << params[:label_selector].to_s
    {true, @servers}
  end
end

private class RecordingSSH < Util::SSH
  getter commands = [] of String
  property node_states = ""

  def initialize
    super("/nonexistent/key")
  end

  property fail_on = ""

  def run(instance, port, command, use_ssh_agent, print_output = true, disable_log_prefix = false, capture_output = false)
    @commands << command
    return node_states if command.includes?("kubectl get nodes")

    raise "host unreachable" if !fail_on.empty? && instance.name == fail_on

    ""
  end

  def installs
    commands.count { |command| command.includes?("k3s worker installation") }
  end
end

private class SynchroniserSetup
  getter synchroniser : Kubernetes::Worker::AutoscaledSynchroniser
  getter client : FakeHetznerClient
  getter ssh : RecordingSSH

  def initialize(@synchroniser, @client, @ssh)
  end
end

private def instance_json(name : String, status = "running")
  %({"id": 1, "name": "#{name}", "status": "#{status}", "public_net": {"ipv4": {"ip": "192.0.2.10"}}})
end

# The synchroniser is built against a loader that stays open for the example.
private def with_synchroniser(yaml : String, &)
  RoutingSpec.with_loader(yaml) do |loader|
    # The generator looks the join token up over SSH; without masters no SSH happens, and the result
    # is cached for the rest of the process.
    K3s.k3s_token(loader.settings, [] of Hetzner::Instance)

    client = FakeHetznerClient.new
    ssh = RecordingSSH.new
    generator = Kubernetes::Script::WorkerGenerator.new(loader, loader.settings)
    synchroniser = Kubernetes::Worker::AutoscaledSynchroniser.new(loader, loader.settings, ssh, generator, client)

    yield SynchroniserSetup.new(synchroniser, client, ssh), loader
  end
end

# The shared config only has an external pool, so the autoscaling pool is written here.
private def autoscaled_config(mentioned : Bool = true)
  head = RoutingSpec.config(false).split("worker_node_pools:").first.not_nil!

  head + <<-YAML
synchronise_autoscaled_nodes: true
worker_node_pools:
- name: pool
  instance_type: cpx22
  location: nbg1
  autoscaling:
    enabled: true
    min_instances: 0
    max_instances: 3
YAML
end

describe "the autoscaled synchronisation flag" do
  it "is off by default" do
    Configuration::Main.from_yaml(RoutingSpec.config(false)).synchronise_autoscaled_nodes.should be_false
  end

  it "is read from the config" do
    Configuration::Main.from_yaml(autoscaled_config).synchronise_autoscaled_nodes.should be_true
  end
end

describe "autoscaled node synchronisation" do
  it "looks nodes up through their node group label" do
    with_synchroniser(autoscaled_config) do |setup|
      setup.client.servers = %({"servers": [#{instance_json("c-node-pool-abc")}]})
      setup.ssh.node_states = "c-node-pool-abc True <none>\n"

      setup.synchroniser.run([RoutingSpec.master], RoutingSpec.master)

      setup.client.selectors.first.should contain("hcloud/node-group=")
      setup.client.selectors.first.should contain("pool")
    end
  end

  it "updates a ready node" do
    with_synchroniser(autoscaled_config) do |setup|
      setup.client.servers = %({"servers": [#{instance_json("c-node-pool-abc")}]})
      setup.ssh.node_states = "c-node-pool-abc True <none>\n"

      counters = setup.synchroniser.run([RoutingSpec.master], RoutingSpec.master)

      counters[:updated].should eq(1)
      setup.ssh.installs.should eq(1)
    end
  end

  it "skips a node that is not ready yet" do
    with_synchroniser(autoscaled_config) do |setup|
      setup.client.servers = %({"servers": [#{instance_json("c-node-pool-abc")}]})
      setup.ssh.node_states = "c-node-pool-abc False <none>\n"

      counters = setup.synchroniser.run([RoutingSpec.master], RoutingSpec.master)

      counters[:skipped].should eq(1)
      setup.ssh.installs.should eq(0)
    end
  end

  it "skips a node the autoscaler has cordoned" do
    with_synchroniser(autoscaled_config) do |setup|
      setup.client.servers = %({"servers": [#{instance_json("c-node-pool-abc")}]})
      setup.ssh.node_states = "c-node-pool-abc True true\n"

      counters = setup.synchroniser.run([RoutingSpec.master], RoutingSpec.master)

      counters[:skipped].should eq(1)
      setup.ssh.installs.should eq(0)
    end
  end

  it "ignores nodes the API reports as deleting" do
    with_synchroniser(autoscaled_config) do |setup|
      setup.client.servers = %({"servers": [#{instance_json("c-node-pool-abc", "deleting")}]})
      setup.ssh.node_states = "c-node-pool-abc True <none>\n"

      counters = setup.synchroniser.run([RoutingSpec.master], RoutingSpec.master)

      counters[:updated].should eq(0)
      counters[:skipped].should eq(0)
    end
  end

  it "keeps going when a node cannot be reached" do
    with_synchroniser(autoscaled_config) do |setup|
      setup.client.servers = %({"servers": [#{instance_json("c-node-pool-abc")}, #{instance_json("c-node-pool-def")}]})
      setup.ssh.node_states = "c-node-pool-abc True <none>\nc-node-pool-def True <none>\n"
      setup.ssh.fail_on = "c-node-pool-def"

      counters = setup.synchroniser.run([RoutingSpec.master], RoutingSpec.master)

      counters[:updated].should eq(1)
      counters[:failed].should eq(1)
    end
  end

  it "does nothing when no pool is autoscaling" do
    with_synchroniser(RoutingSpec.config(false)) do |setup|
      setup.client.servers = %({"servers": [#{instance_json("c-node-pool-abc")}]})
      setup.ssh.node_states = "c-node-pool-abc True <none>\n"

      counters = setup.synchroniser.run([RoutingSpec.master], RoutingSpec.master)

      counters[:updated].should eq(0)
      setup.client.selectors.should be_empty
    end
  end
end
