require "./routing_spec_helper"

# gVisor is opt-in and adds a runtime to containerd, which k3s reads only at startup. These examples
# pin the three things the addon has to get right: it stays out of the rendered script while disabled,
# it installs a pinned runsc build and registers the runtime when enabled, and it restarts k3s on a
# node that already exists so the runtime is actually loaded.
GVISOR_STUBS = <<-BASH
  apt-get() { :; }
  gpg() { :; }
  dpkg() { echo amd64; }
  runsc() { :; }
  BASH

private def gvisor_yaml(enabled : Bool = true, schedulable : Bool = false, version : String? = nil)
  builder = String::Builder.new
  builder << "addons:\n  gvisor:\n    enabled: #{enabled}\n"
  builder << "    version: \"#{version}\"\n" if version
  builder << "schedule_workloads_on_masters: #{schedulable}\n"

  RoutingSpec.config + "\n" + builder.to_s
end

describe Configuration::Models::AddonsConfig::GVisor do
  it "is disabled by default and pins the runsc build" do
    model = Configuration::Models::AddonsConfig::GVisor.new

    model.enabled?.should be_false
    model.version.should eq(Configuration::Models::AddonsConfig::GVisor::DEFAULT_VERSION)
    model.version.should match(/^\d{8}\.\d+$/)
    Configuration::Main.from_yaml(RoutingSpec.config).addons.gvisor.enabled?.should be_false
  end

  it "reads the toggle and the version" do
    settings = Configuration::Main.from_yaml(gvisor_yaml(version: "20250101.0"))

    settings.addons.gvisor.enabled?.should be_true
    settings.addons.gvisor.version.should eq("20250101.0")
  end
end

describe "gVisor node scripts" do
  it "renders nothing for gVisor while the addon is disabled" do
    RoutingSpec.with_loader(gvisor_yaml(enabled: false)) do |loader|
      [RoutingSpec.worker_script(loader), RoutingSpec.master_script(loader)].each do |script|
        script.should_not contain("runsc")
        script.should_not contain("agent/etc/containerd")
      end
    end
  end

  it "installs the pinned runsc build and registers the containerd runtime" do
    RoutingSpec.with_loader(gvisor_yaml(version: "20250101.0")) do |loader|
      [RoutingSpec.worker_script(loader), RoutingSpec.master_script(loader)].each do |script|
        script.should contain(%(GVISOR_VERSION="20250101.0"))
        script.should contain(%(apt-get install -y "runsc=$GVISOR_VERSION"))
        script.should contain(%([plugins."io.containerd.grpc.v1.cri".containerd.runtimes.runsc]))
        script.should contain("command -v apt-get")
        script.should contain("containerd_changed=false")
      end
    end
  end

  it "restarts k3s-agent on an existing worker when the containerd template is new" do
    RoutingSpec.with_loader(gvisor_yaml) do |loader|
      result = RoutingSpec.install(RoutingSpec.worker_script(loader),
        unit_present: true, registries: RoutingSpec.registries(loader), extra_stubs: GVISOR_STUBS)

      result[:success].should be_true
      result[:output].should contain("containerd gVisor configuration changed; restarting k3s-agent")
      result[:calls].should contain("systemctl restart k3s-agent")
      result[:containerd_template].as(String).should contain(%(runtime_type = "io.containerd.runsc.v1"))
    end
  end

  it "leaves systemd alone on a worker that already has the template" do
    RoutingSpec.with_loader(gvisor_yaml) do |loader|
      script = RoutingSpec.worker_script(loader)
      first = RoutingSpec.install(script,
        unit_present: true, registries: RoutingSpec.registries(loader), extra_stubs: GVISOR_STUBS)
      template = first[:containerd_template].as(String)

      second = RoutingSpec.install(script,
        unit_present: true, registries: RoutingSpec.registries(loader), extra_stubs: GVISOR_STUBS,
        containerd_template: template)

      second[:success].should be_true
      second[:output].should_not contain("containerd gVisor configuration changed")
      second[:calls].should_not contain("systemctl restart k3s-agent")
      second[:containerd_template].should eq(template)
    end
  end

  it "restarts k3s on a master that can schedule workloads" do
    RoutingSpec.with_loader(gvisor_yaml(schedulable: true)) do |loader|
      result = RoutingSpec.install(RoutingSpec.master_script(loader), agent_state: "active", extra_stubs: GVISOR_STUBS)

      result[:success].should be_true
      result[:calls].should contain("systemctl restart k3s")
      result[:output].should contain("restarting k3s so runsc is loaded")
    end
  end

  it "keeps the new template without restarting a master that cannot schedule workloads" do
    RoutingSpec.with_loader(gvisor_yaml(schedulable: false)) do |loader|
      result = RoutingSpec.install(RoutingSpec.master_script(loader), agent_state: "active", extra_stubs: GVISOR_STUBS)

      result[:success].should be_true
      result[:calls].should_not contain("systemctl restart k3s")
      result[:output].should contain("takes effect when k3s next restarts on this master")
      result[:containerd_template].as(String).should contain(%(runtime_type = "io.containerd.runsc.v1"))
    end
  end
end
