require "./routing_spec_helper"
require "../src/cluster/instance_builder"

# instance_config is private, and the request hash is exactly what the flag changes.
class Hetzner::Instance::Create
  def spec_request
    instance_config
  end
end

private def placement_settings(flag : Bool?) : Configuration::Main
  yaml = {
    "config_format_version" => 1,
    "hetzner_token"         => "",
    "cluster_name"          => "placement-test",
    "kubeconfig_path"       => "/nonexistent/kubeconfig",
    "k3s_version"           => "v1.35.0+k3s1",
    "networking"            => {"private_network" => {"enabled" => false}},
    "masters_pool"          => {"instance_type" => "cpx22", "instance_count" => 3, "locations" => ["fsn1", "fsn1", "nbg1"]},
    "worker_node_pools"     => [
      {"name" => "db", "instance_type" => "cpx32", "instance_count" => 2, "location" => "fsn1"},
    ],
  }.to_yaml

  yaml += "placement_groups_enabled: #{flag}\n" unless flag.nil?
  Configuration::Main.from_yaml(yaml)
end

private def placement_builder(settings : Configuration::Main, groups : Cluster::PlacementGroupManager::PlacementGroups) : Cluster::InstanceBuilder
  ssh_key = Hetzner::SSHKey.from_json(%({"id": 1, "name": "key", "fingerprint": "fingerprint"}))
  Cluster::InstanceBuilder.new(settings, Hetzner::Client.new(nil), Mutex.new, ssh_key, nil, groups)
end

private def groups_with_masters_and_pool : Cluster::PlacementGroupManager::PlacementGroups
  groups = Cluster::PlacementGroupManager::PlacementGroups.new
  groups.masters = [Hetzner::PlacementGroup.from_json(%({"id": 7, "name": "test-masters-pg1", "type": "spread"}))]
  groups.workers["db"] = [Hetzner::PlacementGroup.from_json(%({"id": 8, "name": "test-db-pg1", "type": "spread"}))]
  groups
end

describe "placement_groups_enabled" do
  it "defaults to off so existing configurations do not start creating groups" do
    placement_settings(nil).placement_groups_enabled.should be_false
    placement_settings(false).placement_groups_enabled.should be_false
    placement_settings(true).placement_groups_enabled.should be_true
  end

  it "builds every instance without a placement group while the flag is off" do
    settings = placement_settings(nil)
    builder = placement_builder(settings, Cluster::PlacementGroupManager::PlacementGroups.new)

    masters = builder.initialize_master_instances(["fsn1", "fsn1", "nbg1"])
    workers = builder.initialize_worker_instances

    masters.size.should eq(3)
    workers.size.should eq(2)
    (masters + workers).each do |instance|
      instance.spec_request.has_key?(:placement_group).should be_false
    end
  end

  it "puts masters and pool workers in their own groups when the flag is on" do
    settings = placement_settings(true)
    builder = placement_builder(settings, groups_with_masters_and_pool)

    masters = builder.initialize_master_instances(["fsn1", "fsn1", "nbg1"])
    workers = builder.initialize_worker_instances

    masters.map { |instance| instance.spec_request[:placement_group] }.uniq.should eq([7])
    workers.map { |instance| instance.spec_request[:placement_group] }.uniq.should eq([8])
  end
end
