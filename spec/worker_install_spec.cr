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

  it "leaves a running, failed or restarting k3s-agent alone after a successful installer run" do
    RoutingSpec.with_loader do |loader|
      ["active", "failed", "activating"].each do |state|
        result = RoutingSpec.install(RoutingSpec.worker_script(loader), agent_state: state)
        result[:success].should be_true
        result[:calls].none?(&.starts_with?("systemctl start")).should be_true
      end
    end
  end

  it "treats a failed installer start as recovered once systemd has restarted the agent" do
    RoutingSpec.with_loader do |loader|
      result = RoutingSpec.install(RoutingSpec.worker_script(loader), installer_exit: 1, agent_state: "active")
      result[:success].should be_true
      result[:output].should contain("k3s-agent is active after a failed first start")
      result[:output].should contain("k3s worker installation completed successfully")
    end
  end

  it "fails the install, with the agent's journal, when the agent never comes up" do
    RoutingSpec.with_loader do |loader|
      result = RoutingSpec.install(RoutingSpec.worker_script(loader), installer_exit: 1, agent_state: "failed", allow_sleep: true)
      result[:success].should be_false
      result[:output].should contain("ERROR: k3s worker installation failed")
      result[:calls].any?(&.starts_with?("journalctl -u k3s-agent")).should be_true
    end
  end
end
