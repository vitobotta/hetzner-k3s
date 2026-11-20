require "./routing_spec_helper"
require "../src/kubernetes/software/cluster_autoscaler"

# The certificate path and the join token are read over SSH, which the offline suite cannot reach.
private class OfflineSSH < Util::SSH
  def initialize
    super("/nonexistent/key")
  end

  def run(instance, port, command, use_ssh_agent, print_output = true, disable_log_prefix = false, capture_output = false)
    "/etc/ssl/certs/ca-certificates.crt\n"
  end
end

private class AutoscalerProbe < Kubernetes::Software::ClusterAutoscaler
  def render_deployments : Array(String)
    resources = YAML.parse_all({{ read_file("#{__DIR__}/../templates/cluster_autoscaler.yaml") }}).map { |document| document }
    patch_resources(resources).map(&.to_yaml)
  end
end

# The registry content only reaches the checksum through the node pools' cloud-init, so the config
# needs an autoscaling pool.
private def rendered(registry : String) : String
  yaml = RoutingSpec.config(false).split("worker_node_pools:").first.not_nil! + <<-YAML
worker_node_pools:
- name: pool
  instance_type: cpx22
  location: nbg1
  autoscaling:
    enabled: true
    min_instances: 0
    max_instances: 3
addons:
  embedded_registry_mirror:
    enabled: true
    private_registry_config: "#{registry}"
YAML

  output = ""
  RoutingSpec.with_loader(yaml) do |loader|
    K3s.k3s_token(loader.settings, [] of Hetzner::Instance)
    pools = loader.settings.worker_node_pools.select(&.autoscaling_enabled)
    probe = AutoscalerProbe.new(loader, loader.settings, [RoutingSpec.master], RoutingSpec.master, OfflineSSH.new, pools)
    output = probe.render_deployments.join
  end
  output
end

describe "cluster autoscaler pod template" do
  it "carries a checksum of the generated node config" do
    rendered("mirrors: {}").should contain("hetzner-k3s/cluster-config-checksum")
  end

  it "keeps the checksum stable for an unchanged config" do
    first = rendered("mirrors: {}").lines.find { |line| line.includes?("cluster-config-checksum") }
    second = rendered("mirrors: {}").lines.find { |line| line.includes?("cluster-config-checksum") }

    first.should eq(second)
  end

  it "changes the checksum when the registry config changes" do
    first = rendered("mirrors: {}").lines.find { |line| line.includes?("cluster-config-checksum") }
    second = rendered("mirrors: { a: b }").lines.find { |line| line.includes?("cluster-config-checksum") }

    first.should_not eq(second)
  end
end
