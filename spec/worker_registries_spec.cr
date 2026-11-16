require "./routing_spec_helper"

# The worker script is re-run on every `create`, so it must put k3s in the state the config asks for
# without interrupting a node that is already in it. registries.yaml is the one file k3s reads only
# at startup, so it is the only one that needs a restart, and only when its content differs.
describe "worker script registry handling" do
  it "does not restart k3s-agent when registries.yaml is already identical" do
    RoutingSpec.with_loader do |loader|
      result = RoutingSpec.install(RoutingSpec.worker_script(loader), registries: RoutingSpec.registries(loader), unit_present: true)

      result[:success].should be_true
      result[:calls].should_not contain("systemctl restart k3s-agent")
      result[:output].should_not contain("registries.yaml changed")
    end
  end

  it "restarts k3s-agent when registries.yaml differs" do
    RoutingSpec.with_loader do |loader|
      result = RoutingSpec.install(RoutingSpec.worker_script(loader), registries: "mirrors: {}\n", unit_present: true)

      result[:success].should be_true
      result[:output].should contain("registries.yaml changed; restarting k3s-agent so k3s re-reads it")
      result[:calls].should contain("systemctl restart k3s-agent")
    end
  end

  it "writes the new content when it differs" do
    RoutingSpec.with_loader do |loader|
      rendered = RoutingSpec.registries(loader)
      result = RoutingSpec.install(RoutingSpec.worker_script(loader), registries: "mirrors: {}\n", unit_present: true)

      result[:registries].should eq(rendered)
    end
  end

  it "keeps the file untouched when it is identical" do
    RoutingSpec.with_loader do |loader|
      rendered = RoutingSpec.registries(loader)
      result = RoutingSpec.install(RoutingSpec.worker_script(loader), registries: rendered, unit_present: true)

      result[:registries].should eq(rendered)
    end
  end

  it "does not restart on a first boot, where the installer starts the agent itself" do
    RoutingSpec.with_loader do |loader|
      result = RoutingSpec.install(RoutingSpec.worker_script(loader), agent_state: "inactive")

      result[:success].should be_true
      result[:calls].should_not contain("systemctl restart k3s-agent")
    end
  end
end
