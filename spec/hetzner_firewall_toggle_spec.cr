require "./routing_spec_helper"
require "../src/cluster/firewall_manager"
require "../src/kubernetes/software/cluster_autoscaler"

private def firewall_yaml(use_hetzner_firewall : Bool? = nil, use_local_firewall : Bool? = nil)
  yaml = RoutingSpec.config.sub("hetzner_token: \"\"", "hetzner_token: fake")
  yaml = yaml.sub("public_network:\n", "public_network:\n    use_hetzner_firewall: #{use_hetzner_firewall}\n") unless use_hetzner_firewall.nil?
  yaml = yaml.sub(/use_local_firewall: \w+/, "use_local_firewall: #{use_local_firewall}") unless use_local_firewall.nil?

  yaml
end

private class FakeFirewallAction
  getter calls = 0

  def run
    @calls += 1
    nil
  end
end

private class RecordingFirewallManager < FirewallManager
  getter created = FakeFirewallAction.new
  getter deleted = FakeFirewallAction.new

  def firewall_creator(master_instances)
    created
  end

  def firewall_deleter
    deleted
  end
end

private def with_manager(yaml : String, &)
  RoutingSpec.with_loader(yaml) do |loader|
    manager = RecordingFirewallManager.new(loader.settings, loader.hetzner_client)
    yield manager
  end
end

private def env_var_names(enabled_hetzner_firewall : Bool)
  names = [] of String

  RoutingSpec.with_loader(firewall_yaml(use_hetzner_firewall: enabled_hetzner_firewall)) do |loader|
    autoscaler = Kubernetes::Software::ClusterAutoscaler.new(
      loader, loader.settings, [] of Hetzner::Instance, RoutingSpec.master, Util::SSH.new("~/.ssh/id_rsa"), [] of Configuration::Models::WorkerNodePool
    )

    container = Kubernetes::Resources::Pod::Spec::Container.from_yaml({"name" => "cluster-autoscaler", "image" => "x", "args" => ["--x"]}.to_yaml)
    autoscaler.configure_container_environment(container)

    names = (container.env || [] of Kubernetes::Resources::Pod::Spec::Container::EnvVariable).map(&.name)
  end

  names
end

describe Configuration::Models::NetworkingConfig::PublicNetwork do
  it "creates the Hetzner firewall by default" do
    model = Configuration::Main.from_yaml(RoutingSpec.config).networking.public_network

    model.use_hetzner_firewall.should be_true
    model.use_local_firewall.should be_false
  end

  it "reads the setting from the config" do
    Configuration::Main.from_yaml(firewall_yaml(use_hetzner_firewall: false)).networking.public_network.use_hetzner_firewall.should be_false
  end
end

describe FirewallManager do
  it "creates and updates the firewall by default" do
    with_manager(firewall_yaml) do |manager|
      manager.handle([] of Hetzner::Instance)

      manager.created.calls.should eq(1)
      manager.deleted.calls.should eq(0)
    end
  end

  it "removes the Hetzner firewall when it is disabled" do
    with_manager(firewall_yaml(use_hetzner_firewall: false)) do |manager|
      manager.handle([] of Hetzner::Instance)

      manager.deleted.calls.should eq(1)
      manager.created.calls.should eq(0)
    end
  end

  it "still removes a leftover firewall with the local firewall active" do
    with_manager(firewall_yaml(use_hetzner_firewall: false, use_local_firewall: true)) do |manager|
      manager.handle([] of Hetzner::Instance)

      manager.deleted.calls.should eq(1)
    end
  end

  it "leaves the Hetzner firewall alone with only the local firewall active" do
    with_manager(firewall_yaml(use_local_firewall: true)) do |manager|
      manager.handle([] of Hetzner::Instance)

      manager.created.calls.should eq(0)
      manager.deleted.calls.should eq(0)
    end
  end
end

describe Kubernetes::Software::ClusterAutoscaler do
  it "passes the firewall name to the autoscaler by default" do
    env_var_names(true).should contain("HCLOUD_FIREWALL")
  end

  it "omits the firewall name when the Hetzner firewall is disabled" do
    env_var_names(false).should_not contain("HCLOUD_FIREWALL")
    env_var_names(false).should contain("HCLOUD_NETWORK")
  end
end
