require "./routing_spec_helper"
require "../src/hetzner/instance/create"

# cloud-init runs the init scripts with sh, not bash, so anything bash-only in them breaks the run
# before the initialized marker is written and leaves the node half configured.
describe "cloud-init compatibility" do
  it "invokes the init scripts with bash" do
    RoutingSpec.with_loader do |loader|
      user_data = Hetzner::Instance::Create.cloud_init(loader.settings, 22, "default",
        [] of String, [] of String, [] of String, ["k3s install"], true)

      user_data.should contain("- bash /etc/init-0.sh")
    end
  end

  it "runs the worker script to completion under sh" do
    RoutingSpec.with_loader do |loader|
      result = RoutingSpec.install(RoutingSpec.worker_script(loader), shell: "sh")

      result[:output].should_not contain("Bad substitution")
      result[:success].should be_true
      result[:initialized].should eq("true\n")
    end
  end

  it "runs the master script to completion under sh" do
    RoutingSpec.with_loader do |loader|
      result = RoutingSpec.install(RoutingSpec.master_script(loader), "192.0.2.5 10.20.0.5", shell: "sh")

      result[:output].should_not contain("Bad substitution")
      result[:success].should be_true
      result[:output].should contain("k3s installation completed successfully")
    end
  end

  it "pins the k3s installer download to https" do
    RoutingSpec.with_loader do |loader|
      RoutingSpec.worker_script(loader).should contain("--proto '=https' --tlsv1.2 -sfL https://get.k3s.io")
      RoutingSpec.master_script(loader).should contain("--proto '=https' --tlsv1.2 -sfL https://get.k3s.io")
    end
  end

  it "keeps the installer failure status intact under sh" do
    RoutingSpec.with_loader do |loader|
      result = RoutingSpec.install(RoutingSpec.worker_script(loader), installer_exit: 1, agent_state: "active", shell: "sh")

      result[:success].should be_false
      result[:output].should contain("ERROR: k3s worker installation failed")
      # the marker stays empty on failure, which is how an unfinished install is detected
      result[:initialized].should eq("")
    end
  end
end
