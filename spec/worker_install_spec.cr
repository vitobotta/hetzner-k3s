require "./routing_spec_helper"

describe "Worker install script" do
  it "starts a k3s-agent the installer left inactive (unit unchanged, service start skipped)" do
    RoutingSpec.with_loader do |loader|
      result = RoutingSpec.install(RoutingSpec.worker_script(loader), agent_state: "inactive")
      result[:success].should be_true
      result[:calls].should contain("systemctl start k3s-agent")
      result[:output].should contain("k3s-agent is not running after the installer")
      result[:output].should contain("k3s worker installation completed successfully")
    end
  end

  it "starts a k3s-agent the installer left failed" do
    RoutingSpec.with_loader do |loader|
      result = RoutingSpec.install(RoutingSpec.worker_script(loader), agent_state: "failed")
      result[:success].should be_true
      result[:calls].should contain("systemctl start k3s-agent")
    end
  end

  it "leaves a running k3s-agent alone after a successful installer run" do
    RoutingSpec.with_loader do |loader|
      result = RoutingSpec.install(RoutingSpec.worker_script(loader), agent_state: "active")
      result[:success].should be_true
      result[:calls].none?(&.starts_with?("systemctl start")).should be_true
    end
  end

  it "leaves a k3s-agent that systemd is already starting alone after a successful installer run" do
    RoutingSpec.with_loader do |loader|
      result = RoutingSpec.install(RoutingSpec.worker_script(loader), agent_state: "activating")
      result[:success].should be_true
      result[:calls].none?(&.starts_with?("systemctl start")).should be_true
    end
  end

  it "treats a failed installer start as recovered once systemd has restarted the agent" do
    RoutingSpec.with_loader do |loader|
      # A new node: no agent before the installer, a restart pending after its failed start, then up.
      result = RoutingSpec.install(RoutingSpec.worker_script(loader), installer_exit: 1, agent_state: "inactive activating active", allow_sleep: true)
      result[:success].should be_true
      result[:output].should contain("k3s-agent is active after a failed first start")
      result[:output].should contain("k3s worker installation completed successfully")
    end
  end

  it "recovers when starting a stopped agent fails and systemd restarts it" do
    RoutingSpec.with_loader do |loader|
      # An in-place reinstall: the installer skips the start, the explicit start fails, and
      # systemd brings the unit up on its retry.
      result = RoutingSpec.install(RoutingSpec.worker_script(loader), agent_state: "inactive inactive activating active", start_exit: 1, allow_sleep: true)
      result[:success].should be_true
      result[:output].should contain("k3s-agent is active after a failed first start")
      result[:calls].should contain("systemctl start k3s-agent")
    end
  end

  it "fails the install when the installer fails on a node whose agent was already running" do
    RoutingSpec.with_loader do |loader|
      # A re-run of create on an existing worker: install.sh fetches the binary before it touches
      # systemd, so a download error leaves the previous agent running. That is not a recovery.
      result = RoutingSpec.install(RoutingSpec.worker_script(loader), installer_exit: 1, agent_state: "active")
      result[:success].should be_false
      result[:output].should contain("ERROR: k3s worker installation failed")
      result[:output].should_not contain("systemd restarted it")
      result[:calls].any?(&.starts_with?("journalctl -u k3s-agent")).should be_true
    end
  end

  it "fails fast when the installer fails and no agent is starting" do
    RoutingSpec.with_loader do |loader|
      # The harness exits the script on any sleep unless allow_sleep is set, so this proves no wait.
      result = RoutingSpec.install(RoutingSpec.worker_script(loader), installer_exit: 1, agent_state: "inactive")
      result[:success].should be_false
      result[:output].should contain("ERROR: k3s worker installation failed")
      result[:output].should_not contain("Unexpected retry")
    end
  end

  it "fails fast when the installer fails and the agent is in the failed state" do
    RoutingSpec.with_loader do |loader|
      result = RoutingSpec.install(RoutingSpec.worker_script(loader), installer_exit: 1, agent_state: "failed")
      result[:success].should be_false
      result[:output].should contain("ERROR: k3s worker installation failed")
      result[:output].should_not contain("Unexpected retry")
    end
  end

  it "fails the install, with the agent's journal, when the agent keeps restarting and never comes up" do
    RoutingSpec.with_loader do |loader|
      result = RoutingSpec.install(RoutingSpec.worker_script(loader), installer_exit: 1, agent_state: "inactive activating", allow_sleep: true)
      result[:success].should be_false
      result[:output].should contain("ERROR: k3s worker installation failed")
      result[:calls].count(&.starts_with?("systemctl is-active")).should eq(25) # one sample before the installer, 24 polls
      result[:calls].any?(&.starts_with?("journalctl -u k3s-agent")).should be_true
    end
  end
end
