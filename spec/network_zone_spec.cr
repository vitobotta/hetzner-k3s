require "./routing_spec_helper"
require "../src/cluster/network_manager"

private def zone_manager(locations : Array(String)) : Cluster::NetworkManager
  config = {
    "config_format_version" => 1,
    "hetzner_token"         => "",
    "cluster_name"          => "zone-test",
    "kubeconfig_path"       => "/nonexistent/kubeconfig",
    "k3s_version"           => "v1.35.0+k3s1",
    "networking"            => {"private_network" => {"enabled" => true, "subnet" => "10.20.0.0/16"}},
    "masters_pool"          => {
      "instance_type"  => "cpx22",
      "instance_count" => locations.size,
      "locations"      => locations,
    },
  }.to_yaml

  Cluster::NetworkManager.new(Configuration::Main.from_yaml(config), Hetzner::Client.new(nil))
end

private def zone_network(subnets : String) : Hetzner::Network
  Hetzner::Network.from_json(%({"id": 1, "name": "cluster-a", "ip_range": "10.20.0.0/16", "subnets": [#{subnets}]}))
end

private def cloud_subnet(zone : String, ip_range = %("10.20.1.0/24")) : String
  %({"type": "cloud", "ip_range": #{ip_range}, "network_zone": "#{zone}", "gateway": "10.20.0.1"})
end

describe "private network zone check" do
  it "derives the zone from the locations the masters are configured for" do
    zone_manager(["fsn1"]).required_zone.should eq("eu-central")
    zone_manager(["ash"]).required_zone.should eq("us-east")
    zone_manager(["hil"]).required_zone.should eq("us-west")
    zone_manager(["sin"]).required_zone.should eq("ap-southeast")
  end

  it "accepts a network in the zone of the masters" do
    manager = zone_manager(["fsn1", "fsn1", "nbg1"])
    manager.zone_mismatch?(zone_network(cloud_subnet("eu-central"))).should be_false
  end

  it "accepts a US network for US masters" do
    manager = zone_manager(["ash"])
    manager.zone_mismatch?(zone_network(cloud_subnet("us-east"))).should be_false
  end

  it "rejects a stale EU network for US masters" do
    manager = zone_manager(["ash"])
    manager.zone_mismatch?(zone_network(cloud_subnet("eu-central"))).should be_true
  end

  it "rejects a network with no subnet at all" do
    network = zone_network("")
    network.network_zones.should be_empty
    zone_manager(["ash"]).zone_mismatch?(network).should be_true
  end

  it "decodes a network without a subnets key as having no zone" do
    network = Hetzner::Network.from_json(%({"id": 3, "name": "cluster-c", "ip_range": "10.20.0.0/16"}))
    network.network_zones.should be_empty
    zone_manager(["ash"]).zone_mismatch?(network).should be_true
  end

  it "accepts a network whose subnets cover the zone, wherever it appears in the list" do
    subnets = [cloud_subnet("eu-central"), cloud_subnet("us-west", %("10.21.1.0/24"))].join(",")
    manager = zone_manager(["hil"])
    manager.zone_mismatch?(zone_network(subnets)).should be_false
  end

  it "keeps decoding a subnet the API returns without an ip range" do
    subnets = [cloud_subnet("us-east", %("10.21.1.0/24")), %({"type": "vswitch", "network_zone": "eu-central", "gateway": "10.20.0.1"})].join(",")
    body = %({"networks": [{"id": 4, "name": "cluster-d", "ip_range": "10.20.0.0/16", "subnets": [#{subnets}]}]})

    networks = Hetzner::NetworksList.from_json(body).networks

    networks.size.should eq(1)
    networks.first.network_zones.should eq(["us-east", "eu-central"])
    zone_manager(["ash"]).zone_mismatch?(networks.first).should be_false
  end
end
