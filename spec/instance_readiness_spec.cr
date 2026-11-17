require "./routing_spec_helper"
require "../src/hetzner/instance/create"

# A client that reports whatever state the example sets and records the action calls.
private class FakeInstanceClient < Hetzner::Client
  property status = "starting"
  property attached = false
  property power_on_fails = false
  getter actions = [] of String

  def initialize
    super("fake-token")
  end

  property public_ip : String? = "192.0.2.10"

  def get(path, params : Hash = {} of Symbol => String | Bool | Nil)
    private_net = attached ? %(, "private_net": [{"ip": "10.0.0.9"}]) : ""
    public_net = public_ip ? %({"ipv4": {"ip": "#{public_ip}"}}) : "{}"
    {true, %({"servers": [{"id": 1, "name": "routing-test-worker1", "status": "#{status}", "public_net": #{public_net}#{private_net}}]})}
  end

  def post(path, params = {} of Symbol => String | Bool | Nil)
    @actions << path
    return {false, "action already running"} if power_on_fails
    return {true, ""} if path.ends_with?("/poweron")

    attached = true
    {true, ""}
  end
end

private class FakeReadinessSSH < Util::SSH
  property failures = 0
  property reply = "ready\n"
  getter calls = 0

  def initialize
    super("/nonexistent/key")
  end

  def run(instance, port, command, use_ssh_agent, print_output = true, disable_log_prefix = false, capture_output = false)
    @calls += 1
    if failures > 0
      @failures -= 1
      raise IO::Error.new("Connection refused")
    end

    reply
  end
end

private class CreateProbe < Hetzner::Instance::Create
  getter fake_client = FakeInstanceClient.new
  getter fake_ssh = FakeReadinessSSH.new

  def hetzner_client : Hetzner::Client
    fake_client
  end

  def ssh_client : Util::SSH
    fake_ssh
  end

  # `network` is a private getter set at construction; the attach path needs one.
  def network_override : Hetzner::Network?
  end

  def network_override=(value : Hetzner::Network?) : Nil
    @network = value
  end

  def ready_now : Nil
    ensure_instance_is_ready
  end
end

private def create_probe(loader, network : Hetzner::Network? = nil) : CreateProbe
  probe = CreateProbe.new(
    loader.settings,
    FakeInstanceClient.new,
    Mutex.new,
    "routing-test-worker1",
    "routing-test-worker1",
    "cpx22",
    "ubuntu-24.04",
    Hetzner::SSHKey.from_json(%({"id": 1, "name": "k", "fingerprint": "fp"})),
    network
  )
  probe.readiness_poll = 1.millisecond
  probe.readiness_timeout = 500.milliseconds
  probe.instance_existed = true

  probe
end

describe "instance readiness" do
  it "returns once SSH answers" do
    RoutingSpec.with_loader(RoutingSpec.config(true)) do |loader|
      probe = create_probe(loader)
      probe.fake_client.status = "running"
      probe.fake_client.attached = true

      probe.ready_now
    end
  end

  it "gives up when the instance never reaches the running state" do
    RoutingSpec.with_loader(RoutingSpec.config(true)) do |loader|
      probe = create_probe(loader)
      probe.max_power_on_attempts = 1

      expect_raises(Exception, "did not reach the running state after 1 power on attempts") { probe.ready_now }
    end
  end

  it "gives up when the instance is never attached to the private network" do
    RoutingSpec.with_loader(RoutingSpec.config(true)) do |loader|
      probe = create_probe(loader)
      probe.fake_client.status = "running"
      probe.fake_client.public_ip = nil
      probe.network_override = Hetzner::Network.from_json(%({"id": 7, "name": "n"}))
      probe.max_attach_attempts = 1

      expect_raises(Exception, "was not attached to the private network after 1 attempts") { probe.ready_now }
    end
  end

  it "gives up when the overall deadline passes" do
    RoutingSpec.with_loader(RoutingSpec.config(true)) do |loader|
      probe = create_probe(loader)
      probe.max_power_on_attempts = 10_000
      probe.readiness_timeout = 5.milliseconds

      expect_raises(Exception, "did not become ready within") { probe.ready_now }
    end
  end

  it "reports a rejected action instead of retrying silently" do
    RoutingSpec.with_loader(RoutingSpec.config(true)) do |loader|
      probe = create_probe(loader)
      probe.fake_client.power_on_fails = true
      probe.max_power_on_attempts = 1

      expect_raises(Exception) { probe.ready_now }

      probe.fake_client.actions.should_not be_empty
    end
  end
end

describe "Util::SSH#wait_for_instance" do
  it "reports attempts and the last failure when it runs out" do
    ssh = FakeReadinessSSH.new
    ssh.failures = 99
    instance = Hetzner::Instance.from_json(%({"id": 1, "name": "routing-test-worker1", "status": "running"}))

    error = expect_raises(Util::SSH::WaitTimeout) do
      ssh.wait_for_instance(instance, 22, false, "echo ready", "ready", 2, 1.millisecond)
    end

    error.message.to_s.should contain("after 2 attempts")
    error.message.to_s.should contain("Connection refused")
  end

  it "succeeds on a later attempt" do
    ssh = FakeReadinessSSH.new
    ssh.failures = 2
    instance = Hetzner::Instance.from_json(%({"id": 1, "name": "routing-test-worker1", "status": "running"}))

    ssh.wait_for_instance(instance, 22, false, "echo ready", "ready", 5, 1.millisecond).should eq("ready")
    ssh.calls.should eq(3)
  end

  it "reports a wrong answer as the reason" do
    ssh = FakeReadinessSSH.new
    ssh.reply = "something else\n"
    instance = Hetzner::Instance.from_json(%({"id": 1, "name": "routing-test-worker1", "status": "running"}))

    error = expect_raises(Util::SSH::WaitTimeout) do
      ssh.wait_for_instance(instance, 22, false, "echo other", "ready", 2, 1.millisecond)
    end

    error.message.to_s.should contain("the command output was")
  end
end
