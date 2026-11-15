require "./routing_spec_helper"
require "../src/kubernetes/software/cluster_autoscaler"

# Since 1.35 the autoscaler always watches the DRA resources and the shipped ClusterRole does not
# grant them, so the tool adds the rule for the bundled and for a fetched manifest alike.
private class ClusterRoleProbe < Kubernetes::Software::ClusterAutoscaler
  def rendered(cluster_role : YAML::Any) : YAML::Any
    patch_resources([cluster_role]).first
  end
end

private def probe(yaml : String = RoutingSpec.config(false)) : ClusterRoleProbe
  result = uninitialized ClusterRoleProbe

  RoutingSpec.with_loader(yaml) do |loader|
    result = ClusterRoleProbe.new(loader, loader.settings, [RoutingSpec.master], RoutingSpec.master, Util::SSH.new("/x"), [] of Configuration::Models::WorkerNodePool)
  end

  result
end

private def cluster_role(rules : String = "") : YAML::Any
  YAML.parse(<<-YAML)
kind: ClusterRole
metadata:
  name: cluster-autoscaler
rules:
#{rules}
YAML
end

private def dra_rules(rendered : YAML::Any) : Array(YAML::Any)
  rendered["rules"].as_a.select do |rule|
    rule["apiGroups"]?.try(&.as_a).try(&.any? { |group| group.as_s == "resource.k8s.io" }) || false
  end
end

describe "cluster autoscaler ClusterRole" do
  it "grants the DRA resources the autoscaler watches" do
    rendered = probe.rendered(cluster_role("- apiGroups: [\"\"]\n  resources: [\"nodes\"]\n  verbs: [\"get\"]\n"))

    rules = dra_rules(rendered)
    rules.size.should eq(1)

    resources = rules.first["resources"].as_a.map(&.as_s)
    resources.sort.should eq(%w(deviceclasses resourceclaims resourceslices))
    rules.first["verbs"].as_a.map(&.as_s).sort.should eq(%w(get list watch))
  end

  it "adds it to the bundled manifest" do
    bundle = YAML.parse_all({{ read_file("#{__DIR__}/../templates/cluster_autoscaler.yaml") }})
    role = bundle.find { |document| document["kind"]?.try(&.as_s) == "ClusterRole" }.not_nil!

    dra_rules(probe.rendered(role)).size.should eq(1)
  end

  it "does not add a second rule when one already covers them" do
    existing = "- apiGroups: [\"resource.k8s.io\"]\n  resources: [\"deviceclasses\", \"resourceslices\", \"resourceclaims\"]\n  verbs: [\"watch\", \"list\", \"get\"]\n"
    rendered = probe.rendered(cluster_role(existing))

    dra_rules(rendered).size.should eq(1)
  end

  it "completes a partial rule instead of accepting it" do
    rendered = probe.rendered(cluster_role("- apiGroups: [\"resource.k8s.io\"]\n  resources: [\"deviceclasses\"]\n  verbs: [\"watch\", \"list\", \"get\"]\n"))

    dra_rules(rendered).size.should eq(2)
  end
end
