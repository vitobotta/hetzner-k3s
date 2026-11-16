require "./routing_spec_helper"
require "../src/kubernetes/software/local_path_storage_class"

private def local_path_yaml(enabled : Bool? = nil, addon_default : Bool? = nil)
  builder = String::Builder.new
  builder << "addons:\n  local_path_storage_class:\n"
  builder << "    enabled: #{enabled}\n" unless enabled.nil?
  builder << "    default: #{addon_default}\n" unless addon_default.nil?

  RoutingSpec.config + "\n" + builder.to_s
end

private def validator_errors(enabled : Bool, addon_default : Bool)
  errors = [] of String
  model = Configuration::Models::AddonsConfig::LocalPathStorageClass.new(enabled, addon_default)
  Configuration::Validators::AddonsConfig::LocalPathStorageClass.new(errors, model).validate
  errors
end

private class RecordingLocalPathStorageClass < Kubernetes::Software::LocalPathStorageClass
  getter commands = [] of String

  getter wait_timeout_seconds : Int32 = 0
  getter poll_interval_seconds : Int32 = 0

  property storage_class_present : Bool = true
  property current_value : String? = "true"
  # Simulates k3s re-applying its manifest after the patch.
  property revert_patches : Int32 = 0

  def run_shell_command(command : String, kubeconfig_path : String, hetzner_token : String, error_message : String = "", abort_on_error : Bool = true, log_prefix : String = "", print_output : Bool = true) : Util::Shell::CommandResult
    @commands << command

    # Only the annotated path answers, the way kubectl does: a path that misses the annotation
    # prints nothing and still exits 0.
    if command.includes?("jsonpath")
      return Util::Shell::CommandResult.new("", 1) unless storage_class_present
      return Util::Shell::CommandResult.new("", 0) unless command.includes?("{.metadata.annotations.")

      Util::Shell::CommandResult.new(current_value.to_s, 0)
    elsif command.includes?("kubectl annotate")
      return Util::Shell::CommandResult.new("", 1) unless storage_class_present

      if revert_patches > 0
        @revert_patches -= 1
        @current_value = "true"
      else
        @current_value = command.split('=').last.split(' ').first
      end

      Util::Shell::CommandResult.new("annotated", 0)
    else
      return Util::Shell::CommandResult.new("", 1) unless storage_class_present

      Util::Shell::CommandResult.new("storageclass.storage.k8s.io/local-path", 0)
    end
  end

  def patches
    commands.select(&.includes?("kubectl annotate"))
  end
end

private def with_configurator(yaml : String, &)
  RoutingSpec.with_loader(yaml) do |loader|
    configurator = RecordingLocalPathStorageClass.new(loader, loader.settings)
    yield configurator
  end
end

describe Configuration::Models::AddonsConfig::LocalPathStorageClass do
  it "is disabled by default" do
    model = Configuration::Models::AddonsConfig::LocalPathStorageClass.new

    model.enabled?.should be_false
    model.default?.should be_true
    Configuration::Main.from_yaml(RoutingSpec.config).addons.local_path_storage_class.enabled?.should be_false
  end

  it "reads the toggle and the default flag" do
    model = Configuration::Main.from_yaml(local_path_yaml(enabled: true, addon_default: false)).addons.local_path_storage_class

    model.enabled?.should be_true
    model.default?.should be_false
  end
end

describe Configuration::Validators::AddonsConfig::LocalPathStorageClass do
  it "accepts the defaults" do
    validator_errors(enabled: false, addon_default: true).should be_empty
  end

  it "accepts an enabled non-default class" do
    validator_errors(enabled: true, addon_default: false).should be_empty
  end

  it "rejects a non-default flag while the addon is disabled" do
    validator_errors(enabled: false, addon_default: false).first.should contain("addons.local_path_storage_class.default is false but the addon is disabled")
  end

  it "runs from the create settings validator" do
    cache_path = File.expand_path("#{ENV["HOME"]}/.hetzner-k3s/k3s-releases.yaml")
    unless File.exists?(cache_path) && Time.utc - File.info(cache_path).modification_time <= 7.days
      Dir.mkdir_p(File.dirname(cache_path))
      File.write(cache_path, ["v1.35.0+k3s1"].to_yaml)
    end

    yaml = local_path_yaml(enabled: false, addon_default: false).sub("hetzner_token: \"\"", "hetzner_token: fake")

    RoutingSpec.with_loader(yaml) do |loader|
      errors = [] of String
      Configuration::Validators::CreateSettings.new(
        errors: errors,
        settings: loader.settings,
        kubeconfig_path: loader.kubeconfig_path,
        hetzner_client: loader.hetzner_client,
        masters_pool: loader.masters_pool,
        instance_types: [] of Hetzner::InstanceType,
        all_locations: [] of Hetzner::Location
      ).validate

      errors.any?(&.includes?("local_path_storage_class.default is false")).should be_true
    end
  end
end

describe "the master install script" do
  it "disables the k3s addon only when the class is fully off" do
    RoutingSpec.with_loader(RoutingSpec.config) do |loader|
      RoutingSpec.master_script(loader).lines.map(&.strip).should contain(%(LOCAL_PATH_STORAGE_CLASS="--disable local-storage"))
    end

    RoutingSpec.with_loader(local_path_yaml(enabled: true, addon_default: false)) do |loader|
      script = RoutingSpec.master_script(loader)
      # the rendered condition proves the toggle is substituted, both branch bodies exist either way
      script.should contain(%(if [ "true" = "true" ]; then\n  LOCAL_PATH_STORAGE_CLASS=""))
    end
  end
end

describe Kubernetes::Software::LocalPathStorageClass do
  it "does nothing while the addon is disabled" do
    with_configurator(RoutingSpec.config) do |configurator|
      configurator.configure

      configurator.commands.should be_empty
    end
  end

  it "leaves a default class alone when default is true" do
    with_configurator(local_path_yaml(enabled: true, addon_default: true)) do |configurator|
      configurator.configure

      configurator.patches.should be_empty
    end
  end

  it "removes the default annotation when default is false" do
    with_configurator(local_path_yaml(enabled: true, addon_default: false)) do |configurator|
      configurator.configure

      configurator.patches.size.should eq(1)
      configurator.patches.first.should contain("kubectl annotate storageclass local-path storageclass.kubernetes.io/is-default-class=false --overwrite")
    end
  end

  it "skips the patch when the class is already non-default" do
    with_configurator(local_path_yaml(enabled: true, addon_default: false)) do |configurator|
      configurator.current_value = "false"
      configurator.configure

      configurator.patches.should be_empty
    end
  end

  it "restores the default flag when it is true again after being set to false" do
    with_configurator(local_path_yaml(enabled: true, addon_default: true)) do |configurator|
      configurator.current_value = "false"
      configurator.configure

      configurator.patches.size.should eq(1)
      configurator.patches.first.should contain("is-default-class=true")
    end
  end

  it "retries when k3s writes the flag back" do
    with_configurator(local_path_yaml(enabled: true, addon_default: false)) do |configurator|
      configurator.revert_patches = 1
      configurator.configure

      configurator.patches.size.should eq(2)
    end
  end

  it "raises when the flag never sticks" do
    with_configurator(local_path_yaml(enabled: true, addon_default: false)) do |configurator|
      configurator.revert_patches = 5

      expect_raises(LocalPathStorageClassError, /Could not set storageclass.kubernetes.io\/is-default-class to false/) do
        configurator.configure
      end
    end
  end

  it "gives up quietly when the class never appears" do
    with_configurator(local_path_yaml(enabled: true, addon_default: false)) do |configurator|
      configurator.storage_class_present = false
      configurator.configure

      configurator.patches.should be_empty
      configurator.commands.first.should contain("kubectl get storageclass local-path -o name")
    end
  end
end
