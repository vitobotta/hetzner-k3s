require "./routing_spec_helper"
require "../src/kubernetes/software/cluster_autoscaler"

private def autoscaler_yaml(manifest_url : String? = nil, local_manifest_path : String? = nil)
  builder = String::Builder.new
  builder << "addons:\n  cluster_autoscaler:\n    enabled: true\n"
  builder << "    manifest_url: \"#{manifest_url}\"\n" if manifest_url
  builder << "    local_manifest_path: \"#{local_manifest_path}\"\n" if local_manifest_path

  RoutingSpec.config.sub("hetzner_token: \"\"", "hetzner_token: fake") + "\n" + builder.to_s
end

private class InspectableAutoscaler < Kubernetes::Software::ClusterAutoscaler
  property fetched_url : String? = nil

  def build
    manifest
  end

  private def certificate_path : String
    "/etc/ssl/certs/ca-certificates.crt"
  end

  private def fetch_manifest(url : String) : String
    @fetched_url = url
    {"apiVersion" => "v1", "kind" => "ConfigMap", "metadata" => {"name" => "fetched-marker"}}.to_yaml
  end
end

private def built(yaml : String) : String
  built = ""
  RoutingSpec.with_loader(yaml) do |loader|
    autoscaler = InspectableAutoscaler.new(
      loader, loader.settings, [RoutingSpec.master], RoutingSpec.master, Util::SSH.new("~/.ssh/id_rsa"), [] of Configuration::Models::WorkerNodePool
    )
    built = autoscaler.build
  end

  built
end

describe "the bundled Cluster Autoscaler manifest" do
  it "is used when no manifest is configured" do
    manifest = built(autoscaler_yaml)

    manifest.should contain("name: cluster-autoscaler")
    manifest.should_not contain("fetched-marker")
  end

  it "has no gitlab-registry image pull secret" do
    built(autoscaler_yaml).should_not contain("gitlab-registry")
    built(autoscaler_yaml).should_not contain("imagePullSecrets")
  end

  it "keeps the fields hetzner-k3s patches" do
    manifest = built(autoscaler_yaml)

    manifest.should contain("ssl-certs")
    manifest.should contain("cluster-autoscaler-config")
  end

  it "is replaced by a configured manifest_url" do
    manifest = built(autoscaler_yaml(manifest_url: "https://example.com/autoscaler.yaml"))

    manifest.should contain("fetched-marker")
    manifest.should_not contain("name: cluster-autoscaler")
  end

  it "still prefers a local manifest file" do
    path = File.tempname("autoscaler", ".yaml")
    File.write(path, {"apiVersion" => "v1", "kind" => "ConfigMap", "metadata" => {"name" => "local-marker"}}.to_yaml)

    begin
      manifest = built(autoscaler_yaml(manifest_url: "https://example.com/autoscaler.yaml", local_manifest_path: path))

      manifest.should contain("local-marker")
    ensure
      File.delete(path)
    end
  end

  it "defaults manifest_url to nil so the bundled copy applies" do
    Configuration::Main.from_yaml(RoutingSpec.config).addons.cluster_autoscaler.manifest_url.should be_nil
  end
end
