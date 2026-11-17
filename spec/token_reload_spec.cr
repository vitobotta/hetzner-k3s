require "./routing_spec_helper"
require "../src/kubernetes/software/hetzner/secret"

private def addons_yaml(cloud_controller_manager : Bool? = nil, csi_driver : Bool? = nil, cluster_autoscaler : Bool? = nil)
  builder = String::Builder.new
  builder << "addons:\n"
  builder << "  cloud_controller_manager:\n    enabled: #{cloud_controller_manager}\n" unless cloud_controller_manager.nil?
  builder << "  csi_driver:\n    enabled: #{csi_driver}\n" unless csi_driver.nil?
  builder << "  cluster_autoscaler:\n    enabled: #{cluster_autoscaler}\n" unless cluster_autoscaler.nil?

  RoutingSpec.config + "\n" + builder.to_s
end

private ALL_COMPONENTS = Set{"hcloud-cloud-controller-manager", "hcloud-csi-controller", "hcloud-csi-node", "cluster-autoscaler"}

# Stands in for the reloader so the secret side can be tested without any kubectl traffic.
private class CountingReload < Kubernetes::Software::Hetzner::TokenReload
  getter calls = 0

  def reload : Nil
    @calls += 1
  end
end

private class RecordingSecret < Kubernetes::Software::Hetzner::Secret
  getter reloader = CountingReload.new(LoaderHolder.loader, LoaderHolder.loader.settings)
  property stored_token_b64 : String? = Base64.strict_encode("old-token")

  def run_shell_command(command : String, kubeconfig_path : String, hetzner_token : String, error_message : String = "", abort_on_error : Bool = true, log_prefix : String = "", print_output : Bool = true) : Util::Shell::CommandResult
    if command.includes?("get secret hcloud")
      token = stored_token_b64
      return Util::Shell::CommandResult.new("", 1) if token.nil?

      return Util::Shell::CommandResult.new(token, 0)
    end

    Util::Shell::CommandResult.new("ok", 0)
  end

  private def token_reload : Kubernetes::Software::Hetzner::TokenReload
    reloader
  end
end

# Hands the loader to recording objects that are built before a loader exists.
module LoaderHolder
  class_property loader : Configuration::Loader { raise "loader not set" }
end

private class RecordingReload < Kubernetes::Software::Hetzner::TokenReload
  getter commands = [] of String

  property present_components = ALL_COMPONENTS
  getter poll_interval : Time::Span = 0.seconds
  property rollout_succeeds : Bool = true

  def run_shell_command(command : String, kubeconfig_path : String, hetzner_token : String, error_message : String = "", abort_on_error : Bool = true, log_prefix : String = "", print_output : Bool = true) : Util::Shell::CommandResult
    @commands << command

    if command.includes?("rollout status")
      return rollout_succeeds ? Util::Shell::CommandResult.new("ready", 0) : Util::Shell::CommandResult.new("waiting", 1)
    end

    if match = command.match(/get (deployment|daemonset) (?<name>\S+) -o name/)
      return Util::Shell::CommandResult.new("", 1) unless present_components.includes?(match["name"])

      return Util::Shell::CommandResult.new(match["name"], 0)
    end

    Util::Shell::CommandResult.new("ok", 0)
  end

  def restarts
    commands.select(&.includes?("rollout restart"))
  end

  def status_checks
    commands.select(&.includes?("rollout status"))
  end
end

private def with_loader(yaml : String, &)
  RoutingSpec.with_loader(yaml.sub("hetzner_token: \"\"", "hetzner_token: new-token")) do |loader|
    LoaderHolder.loader = loader
    yield loader
  end
end

private def restarted_names(reloader : RecordingReload) : Array(String)
  reloader.restarts.map { |command| command.split('/').last }
end

describe "the Hetzner secret update" do
  it "reloads the components when the stored token differs" do
    with_loader(addons_yaml) do |loader|
      secret = RecordingSecret.new(loader, loader.settings)
      secret.create

      secret.reloader.calls.should eq(1)
    end
  end

  it "leaves the components alone while the token is unchanged" do
    with_loader(addons_yaml) do |loader|
      secret = RecordingSecret.new(loader, loader.settings)
      secret.stored_token_b64 = Base64.strict_encode("new-token")
      secret.create

      secret.reloader.calls.should eq(0)
    end
  end

  it "reloads when the secret does not exist yet" do
    with_loader(addons_yaml) do |loader|
      secret = RecordingSecret.new(loader, loader.settings)
      secret.stored_token_b64 = nil
      secret.create

      secret.reloader.calls.should eq(1)
    end
  end
end

describe Kubernetes::Software::Hetzner::TokenReload do
  it "restarts every enabled component" do
    with_loader(addons_yaml) do |loader|
      reloader = RecordingReload.new(loader, loader.settings)
      reloader.reload

      restarted_names(reloader).should eq([
        "hcloud-cloud-controller-manager",
        "hcloud-csi-controller",
        "hcloud-csi-node",
        "cluster-autoscaler",
      ])
    end
  end

  it "uses the kube-system namespace for every rollout" do
    with_loader(addons_yaml) do |loader|
      reloader = RecordingReload.new(loader, loader.settings)
      reloader.reload

      reloader.restarts.each(&.should(contain(" -n kube-system rollout restart")))
    end
  end

  it "skips a disabled addon" do
    with_loader(addons_yaml(cloud_controller_manager: false, cluster_autoscaler: false)) do |loader|
      reloader = RecordingReload.new(loader, loader.settings)
      reloader.reload

      restarted_names(reloader).should eq(["hcloud-csi-controller", "hcloud-csi-node"])
    end
  end

  it "skips a component that is not installed" do
    with_loader(addons_yaml) do |loader|
      reloader = RecordingReload.new(loader, loader.settings)
      reloader.present_components = Set{"hcloud-cloud-controller-manager"}
      reloader.reload

      restarted_names(reloader).should eq(["hcloud-cloud-controller-manager"])
    end
  end

  it "does nothing when no component is running" do
    with_loader(addons_yaml) do |loader|
      reloader = RecordingReload.new(loader, loader.settings)
      reloader.present_components = Set(String).new
      reloader.reload

      reloader.restarts.should be_empty
    end
  end

  it "waits for every restarted component to finish" do
    with_loader(addons_yaml) do |loader|
      reloader = RecordingReload.new(loader, loader.settings)
      reloader.reload

      reloader.status_checks.size.should eq(reloader.restarts.size)
    end
  end

  it "logs a stalled rollout instead of failing the run" do
    with_loader(addons_yaml(cloud_controller_manager: false, csi_driver: false)) do |loader|
      reloader = RecordingReload.new(loader, loader.settings)
      reloader.rollout_succeeds = false
      reloader.reload

      reloader.status_checks.size.should eq(3)
    end
  end
end
