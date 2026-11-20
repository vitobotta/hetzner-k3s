require "./routing_spec_helper"
require "../src/kubernetes/software/cluster_autoscaler"

private class AutoscalerArgsProbe < Kubernetes::Software::ClusterAutoscaler
  def command_args : Array(String)
    container_command
  end
end

private def command_for(addon_yaml : String) : Array(String)
  yaml = RoutingSpec.config(false).split("worker_node_pools:").first.not_nil!
  yaml += "addons:\n  cluster_autoscaler:\n#{addon_yaml}"

  args = [] of String
  RoutingSpec.with_loader(yaml) do |loader|
    probe = AutoscalerArgsProbe.new(loader, loader.settings, [RoutingSpec.master], RoutingSpec.master, Util::SSH.new("/x"), [] of Configuration::Models::WorkerNodePool)
    args = probe.command_args
  end
  args
end

describe "new_pod_scale_up_delay" do
  it "is left out of the command when unset, so the autoscaler default stays" do
    command_for("    scan_interval: \"10s\"\n").none?(&.starts_with?("--new-pod-scale-up-delay")).should be_true
  end

  it "reaches the autoscaler command when set" do
    command_for("    new_pod_scale_up_delay: \"45s\"\n").should contain("--new-pod-scale-up-delay=45s")
  end

  it "keeps the other delay flags" do
    args = command_for("    new_pod_scale_up_delay: \"45s\"\n")

    args.should contain("--scan-interval=10s")
    args.should contain("--scale-down-delay-after-add=10m")
    args.should contain("--max-node-provision-time=15m")
  end
end

private def errors_for(addon_yaml : String) : Array(String)
  yaml = RoutingSpec.config(false).split("worker_node_pools:").first.not_nil!
  yaml += "addons:\n  cluster_autoscaler:\n#{addon_yaml}"

  errors = [] of String
  RoutingSpec.with_loader(yaml) do |loader|
    Configuration::Validators::AddonsConfig::ClusterAutoscaler.new(errors, loader.settings.addons.cluster_autoscaler).validate
  end
  errors
end

describe Configuration::Validators::AddonsConfig::ClusterAutoscaler do
  it "accepts the defaults and unset delay" do
    errors_for("    scan_interval: \"10s\"\n").should be_empty
  end

  it "accepts a compound duration" do
    errors_for("    new_pod_scale_up_delay: \"1h30m\"\n").should be_empty
  end

  it "accepts a fractional duration" do
    errors_for("    new_pod_scale_up_delay: \"1.5m\"\n").should be_empty
  end

  it "rejects a number without a unit" do
    errors_for("    new_pod_scale_up_delay: \"45\"\n").first.should contain("new_pod_scale_up_delay must be a duration")
  end

  it "rejects a word" do
    errors_for("    new_pod_scale_up_delay: \"soon\"\n").first.should contain("new_pod_scale_up_delay must be a duration")
  end

  it "is reached through the create settings validation" do
    yaml = RoutingSpec.config(false).sub("hetzner_token:", "hetzner_token: fake")
    yaml += "addons:\n  cluster_autoscaler:\n    new_pod_scale_up_delay: \"soon\"\n"

    errors = [] of String
    RoutingSpec.with_loader(yaml) do |loader|
      Configuration::Validators::CreateSettings.new(
        errors: errors,
        settings: loader.settings,
        kubeconfig_path: loader.kubeconfig_path,
        hetzner_client: loader.hetzner_client,
        masters_pool: loader.masters_pool,
        instance_types: [] of Hetzner::InstanceType,
        all_locations: [] of Hetzner::Location
      ).validate
    end

    errors.any?(&.includes?("new_pod_scale_up_delay must be a duration")).should be_true
  end

  it "rejects a bad value in an existing field too" do
    errors_for("    scale_down_delay_after_add: \"ten minutes\"\n").first.should contain("scale_down_delay_after_add must be a duration")
  end
end
