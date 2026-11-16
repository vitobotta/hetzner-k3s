require "./routing_spec_helper"
require "../src/kubernetes/software/coredns"

private def coredns_yaml(
  enabled : Bool = false,
  replicas : Int32? = nil,
  image : String? = nil,
  requests_cpu : String? = nil,
  requests_memory : String? = nil,
  limits_cpu : String? = nil,
  limits_memory : String? = nil,
  cluster_domain : String? = nil,
)
  builder = String::Builder.new

  builder << "addons:\n  coredns:\n"
  builder << "    enabled: true\n" if enabled
  builder << "    replicas: #{replicas}\n" if replicas
  builder << "    image: \"#{image}\"\n" if image

  if requests_cpu || requests_memory || limits_cpu || limits_memory
    builder << "    resources:\n"
    if requests_cpu || requests_memory
      builder << "      requests:\n"
      builder << "        cpu: #{requests_cpu}\n" if requests_cpu
      builder << "        memory: #{requests_memory}\n" if requests_memory
    end
    if limits_cpu || limits_memory
      builder << "      limits:\n"
      builder << "        cpu: #{limits_cpu}\n" if limits_cpu
      builder << "        memory: #{limits_memory}\n" if limits_memory
    end
  end

  yaml = RoutingSpec.config + "\n" + builder.to_s
  yaml = yaml.sub("\nnetworking:\n", "\nnetworking:\n  cluster_domain: #{cluster_domain}\n  cluster_dns: 10.43.0.99\n") if cluster_domain
  yaml
end

private def validator_errors(
  replicas : Int32? = 1,
  image : String = Configuration::Models::AddonsConfig::CoreDNS::DEFAULT_IMAGE,
  requests_cpu : String? = nil,
  requests_memory : String? = nil,
  limits_cpu : String? = nil,
  limits_memory : String? = nil,
)
  errors = [] of String
  resources = Configuration::Models::AddonsConfig::CoreDNS::Resources.from_yaml({
    "requests" => {"cpu" => requests_cpu, "memory" => requests_memory},
    "limits"   => {"cpu" => limits_cpu, "memory" => limits_memory},
  }.to_yaml)
  model = Configuration::Models::AddonsConfig::CoreDNS.new(false, replicas, image, resources)
  Configuration::Validators::AddonsConfig::CoreDNS.new(errors, model).validate
  errors
end

# The k3s version validator calls the GitHub API unless the release cache is fresh. Prime the
# cache so the create settings example does not depend on the network.
private def prime_k3s_releases_cache
  cache_path = File.expand_path("#{ENV["HOME"]}/.hetzner-k3s/k3s-releases.yaml")
  return if File.exists?(cache_path) && Time.utc - File.info(cache_path).modification_time <= 7.days

  Dir.mkdir_p(File.dirname(cache_path))
  File.write(cache_path, ["v1.35.0+k3s1"].to_yaml)
end

private class RecordingCoreDNS < Kubernetes::Software::CoreDNS
  getter commands = [] of String

  getter missing_deployment_timeout_seconds : Int32 = 0
  getter poll_interval_seconds : Int32 = 0
  property verify_timeout_seconds : Int32 = 0

  property deployment_present : Bool = true
  property managed_label : String = ""
  property current_replicas : String = "1"

  def run_shell_command(command : String, kubeconfig_path : String, hetzner_token : String, error_message : String = "", abort_on_error : Bool = true, log_prefix : String = "", print_output : Bool = true) : Util::Shell::CommandResult
    @commands << command

    if command.includes?("jsonpath='{.spec.replicas}'")
      return Util::Shell::CommandResult.new("", 1) unless deployment_present

      Util::Shell::CommandResult.new(current_replicas, 0)
    elsif command.includes?("jsonpath='{.metadata.labels.hetzner-k3s-managed}'")
      return Util::Shell::CommandResult.new("", 1) unless deployment_present

      Util::Shell::CommandResult.new(managed_label, 0)
    else
      Util::Shell::CommandResult.new("ok", 0)
    end
  end

  def applies
    commands.select(&.includes?("kubectl apply -f")).size
  end
end

private def deployed_limits(manifest : String) : YAML::Any
  deployment = YAML.parse_all(manifest).find { |document| document["kind"]?.try(&.as_s) == "Deployment" }.not_nil!
  deployment["spec"]["template"]["spec"]["containers"][0]["resources"]["limits"]
end

private def with_installer(yaml : String, &)
  RoutingSpec.with_loader(yaml) do |loader|
    installer = RecordingCoreDNS.new(loader, loader.settings)
    yield installer
  end
end

describe Configuration::Models::AddonsConfig::CoreDNS do
  it "is disabled by default, with no replica override and the k3s resource defaults" do
    model = Configuration::Models::AddonsConfig::CoreDNS.new
    model.enabled?.should be_false
    model.replicas.should be_nil
    model.image.should eq(Configuration::Models::AddonsConfig::CoreDNS::DEFAULT_IMAGE)
    model.resources.limits.memory.should be_nil

    Configuration::Main.from_yaml(RoutingSpec.config).addons.coredns.enabled?.should be_false
  end

  it "reads the toggle, resources and image from the config" do
    model = Configuration::Main.from_yaml(coredns_yaml(enabled: true, replicas: 3, image: "example/coredns:9", limits_memory: "1Gi")).addons.coredns

    model.enabled?.should be_true
    model.replicas.should eq(3)
    model.image.should eq("example/coredns:9")
    model.resources.limits.memory.should eq("1Gi")
  end
end

describe Configuration::Validators::AddonsConfig::CoreDNS do
  it "accepts the defaults" do
    validator_errors.should be_empty
  end

  it "accepts an unset replica count" do
    validator_errors(replicas: nil).should be_empty
  end

  it "accepts the bounds and quantities with different suffixes" do
    validator_errors(replicas: 10, requests_cpu: "0.5", limits_cpu: "1").should be_empty
    validator_errors(requests_memory: "512M", limits_memory: "1Gi").should be_empty
  end

  it "rejects a replica count below one, which would leave the cluster without DNS" do
    validator_errors(replicas: 0).join.should contain("addons.coredns.replicas must be between 1 and 10")
  end

  it "rejects an unreasonably high replica count" do
    validator_errors(replicas: 11).join.should contain("between 1 and 10 (found: 11)")
  end

  it "rejects an empty image" do
    validator_errors(image: " ").join.should contain("addons.coredns.image cannot be empty")
  end

  it "rejects malformed quantities" do
    validator_errors(requests_cpu: "100 m").join.should contain("invalid cpu quantity '100 m'")
    validator_errors(limits_memory: "170MB").join.should contain("invalid memory quantity '170MB'")
  end

  it "rejects requests above the matching limit" do
    validator_errors(requests_cpu: "500m", limits_cpu: "250m").join.should contain("requests.cpu (500m) must not exceed")
    validator_errors(requests_memory: "256Mi", limits_memory: "170Mi").join.should contain("requests.memory (256Mi) must not exceed")
  end

  it "surfaces the error through the create settings validation" do
    prime_k3s_releases_cache
    yaml = coredns_yaml(enabled: true, replicas: 0).sub("hetzner_token: \"\"", "hetzner_token: fake")

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

      errors.should contain("addons.coredns.replicas must be between 1 and 10 (found: 0)")
    end
  end
end

describe Kubernetes::Software::CoreDNS do
  it "enables the k3s flag only when the toggle is on" do
    RoutingSpec.with_loader(RoutingSpec.config) do |loader|
      RoutingSpec.master_script(loader).should match(/if \[ "false" = "true" \]; then\n  COREDNS_PLUGIN="--disable coredns"/)
    end

    RoutingSpec.with_loader(coredns_yaml(enabled: true)) do |loader|
      script = RoutingSpec.master_script(loader)
      script.should match(/if \[ "true" = "true" \]; then\n  COREDNS_PLUGIN="--disable coredns"/)
      script.lines.map(&.strip).should contain("$COREDNS_PLUGIN \\")
    end
  end

  describe "#render" do
    it "renders the configured replicas, resources and image" do
      RoutingSpec.with_loader(coredns_yaml(enabled: true, replicas: 3, image: "example/coredns:9", requests_cpu: "250m", limits_memory: "512Mi")) do |loader|
        manifest = Kubernetes::Software::CoreDNS.new(loader, loader.settings).render(managed: true)

        manifest.should contain("replicas: 3")
        manifest.should contain("image: \"example/coredns:9\"")
        manifest.should contain("cpu: 250m")
        manifest.should contain("memory: 512Mi")
        manifest.should contain("hetzner-k3s-managed: coredns")
      end
    end

    it "falls back to the k3s resource defaults" do
      RoutingSpec.with_loader(coredns_yaml(enabled: true)) do |loader|
        manifest = Kubernetes::Software::CoreDNS.new(loader, loader.settings).render(managed: true)

        manifest.should contain("memory: 170Mi")
        manifest.should contain("cpu: 100m")
        manifest.should contain("memory: 70Mi")
        manifest.should contain("replicas: 1")
      end
    end

    it "leaves the cpu limit unset until one is configured" do
      RoutingSpec.with_loader(coredns_yaml(enabled: true)) do |loader|
        limits = deployed_limits(Kubernetes::Software::CoreDNS.new(loader, loader.settings).render(managed: true))

        limits.as_h.has_key?("cpu").should be_true
        limits["cpu"].raw.should be_nil
        limits["memory"].as_s.should eq("170Mi")
      end
    end

    it "renders a configured cpu limit" do
      RoutingSpec.with_loader(coredns_yaml(enabled: true, limits_cpu: "500m")) do |loader|
        deployed_limits(Kubernetes::Software::CoreDNS.new(loader, loader.settings).render(managed: true))["cpu"].as_s.should eq("500m")
      end
    end

    it "keeps the object names and labels the node-local DNS cache depends on" do
      RoutingSpec.with_loader(coredns_yaml(enabled: true)) do |loader|
        manifest = Kubernetes::Software::CoreDNS.new(loader, loader.settings).render(managed: true)

        manifest.should contain("name: kube-dns")
        manifest.should contain("k8s-app: kube-dns")
        manifest.should contain("clusterIP: 10.43.0.10")
        manifest.should contain("kubernetes cluster.local in-addr.arpa ip6.arpa")
      end
    end

    it "uses the configured cluster domain and dns address" do
      yaml = coredns_yaml(enabled: true, cluster_domain: "internal.example")

      RoutingSpec.with_loader(yaml) do |loader|
        manifest = Kubernetes::Software::CoreDNS.new(loader, loader.settings).render(managed: true)

        manifest.should contain("kubernetes internal.example in-addr.arpa ip6.arpa")
        manifest.should contain("clusterIP: 10.43.0.99")
      end
    end

    it "renders a parseable manifest with the expected objects" do
      RoutingSpec.with_loader(coredns_yaml(enabled: true, replicas: 2)) do |loader|
        docs = YAML.parse_all(Kubernetes::Software::CoreDNS.new(loader, loader.settings).render(managed: true))

        docs.map { |doc| doc["kind"].as_s }.should eq(["ServiceAccount", "ClusterRole", "ClusterRoleBinding", "ConfigMap", "Deployment", "Service"])

        deployment = docs.find { |doc| doc["kind"].as_s == "Deployment" }.not_nil!
        deployment["spec"]["replicas"].as_i.should eq(2)
        deployment["spec"]["template"]["spec"]["containers"][0]["resources"]["limits"]["memory"].as_s.should eq("170Mi")
        deployment["spec"]["strategy"]["rollingUpdate"]["maxUnavailable"].as_i.should eq(0)
      end
    end

    it "drops the ownership label for the k3s managed render" do
      RoutingSpec.with_loader(coredns_yaml(enabled: true)) do |loader|
        Kubernetes::Software::CoreDNS.new(loader, loader.settings).render(managed: false).should_not contain("hetzner-k3s-managed")
      end
    end
  end

  describe "#install" do
    it "applies the managed manifest and waits for the rollout when the toggle is on" do
      with_installer(coredns_yaml(enabled: true, replicas: 2)) do |installer|
        installer.managed_label = "coredns"
        installer.install

        installer.applies.should eq(1)
        installer.commands.last.should contain("kubectl rollout status deployment coredns")
        installer.commands.none?(&.starts_with?("kubectl scale")).should be_true
      end
    end

    it "applies again when the k3s prune removes the deployment after the first apply" do
      with_installer(coredns_yaml(enabled: true)) do |installer|
        installer.verify_timeout_seconds = 1
        installer.managed_label = ""
        installer.install

        installer.applies.should eq(2)
      end
    end

    it "hands CoreDNS back to k3s with its defaults when the toggle is off" do
      with_installer(coredns_yaml) do |installer|
        installer.managed_label = "coredns"
        installer.current_replicas = "3"
        installer.install

        installer.applies.should eq(1)
        installer.commands.any?(&.includes?("kubectl label deployment coredns -n kube-system hetzner-k3s-managed-")).should be_true
        installer.commands.last.should contain("kubectl rollout status")
        installer.commands.none?(&.starts_with?("kubectl scale")).should be_true
      end
    end

    it "only reconciles the replica count when k3s still owns the deployment" do
      with_installer(coredns_yaml(replicas: 3)) do |installer|
        installer.current_replicas = "1"
        installer.install

        installer.applies.should eq(0)
        installer.commands.last.should eq("kubectl scale deployment coredns -n kube-system --replicas=3")
      end
    end

    it "does not reset a manually scaled deployment when no replica count is configured" do
      with_installer(RoutingSpec.config) do |installer|
        installer.current_replicas = "3"
        installer.install

        installer.commands.none?(&.starts_with?("kubectl scale")).should be_true
      end
    end

    it "leaves a k3s managed deployment alone when the replica count already matches" do
      with_installer(coredns_yaml(replicas: 2)) do |installer|
        installer.current_replicas = "2"
        installer.install

        installer.commands.should eq([
          "kubectl get deployment coredns -n kube-system -o jsonpath='{.metadata.labels.hetzner-k3s-managed}'",
          "kubectl get deployment coredns -n kube-system -o jsonpath='{.spec.replicas}'",
        ])
      end
    end

    it "leaves everything alone when the deployment does not exist yet" do
      with_installer(coredns_yaml(replicas: 3)) do |installer|
        installer.deployment_present = false
        installer.install

        installer.commands.none?(&.starts_with?("kubectl scale")).should be_true
        installer.applies.should eq(0)
      end
    end
  end
end
