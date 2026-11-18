require "./routing_spec_helper"
require "../src/configuration/validators/api_load_balancer"
require "../src/hetzner/load_balancer/create"

private class FakeLoadBalancerClient < Hetzner::Client
  getter posts = [] of String

  def initialize(@load_balancer_json : String)
    super("fake-token")
  end

  def get(path, params : Hash = {} of Symbol => String | Bool | Nil)
    {true, %({"load_balancers": [#{@load_balancer_json}]})}
  end

  def post(path, params = {} of KeyType => ValueType)
    @posts << path
    {true, "{}"}
  end
end

module ApiLoadBalancerSpec
  NETWORK_ID = 42_i64

  def self.config(create_lb = true, private_network = true, masters = 3)
    RoutingSpec.config(private_network: private_network)
      .sub("instance_count: 3", "instance_count: #{masters}")
      .+("create_load_balancer_for_the_kubernetes_api: #{create_lb}\n")
      .+("disable_public_interface_for_the_kubernetes_api_load_balancer: true\n")
  end

  def self.errors(yaml) : Array(String)
    errors = [] of String
    RoutingSpec.with_loader(yaml) do |loader|
      Configuration::Validators::ApiLoadBalancer.new(errors, loader.settings).validate
    end
    errors
  end

  def self.load_balancer(network = NETWORK_ID, enabled = true, use_private_ip = true)
    Hetzner::LoadBalancer.from_json(load_balancer_json(network, enabled, use_private_ip))
  end

  def self.load_balancer_json(network = NETWORK_ID, enabled = true, use_private_ip = true) : String
    ({
      "id"          => 1,
      "name"        => "routing-test-api",
      "private_net" => [{"ip" => "10.20.0.254", "network" => network}],
      "public_net"  => {"enabled" => enabled, "ipv4" => {"ip" => "198.51.100.7"}},
      "targets"     => [{"use_private_ip" => use_private_ip}],
    }).to_json
  end

  # Runs Create against an existing load balancer with the flag on; returns the client to inspect.
  def self.create(json : String, &)
    client = FakeLoadBalancerClient.new(json)
    RoutingSpec.with_loader(config) do |loader|
      yield Hetzner::LoadBalancer::Create.new(loader.settings, client, "nbg1", NETWORK_ID), client
    end
  end
end

describe Configuration::Validators::ApiLoadBalancer do
  it "accepts a multi-master cluster with the API load balancer and the private network" do
    ApiLoadBalancerSpec.errors(ApiLoadBalancerSpec.config).should be_empty
  end

  it "requires the API load balancer" do
    ApiLoadBalancerSpec.errors(ApiLoadBalancerSpec.config(create_lb: false)).should eq(["disable_public_interface_for_the_kubernetes_api_load_balancer requires create_load_balancer_for_the_kubernetes_api to be enabled"])
  end

  it "requires the private network" do
    ApiLoadBalancerSpec.errors(ApiLoadBalancerSpec.config(private_network: false)).should eq(["disable_public_interface_for_the_kubernetes_api_load_balancer requires the private network to be enabled"])
  end

  it "requires more than one master" do
    errors = ApiLoadBalancerSpec.errors(ApiLoadBalancerSpec.config(masters: 1))
    errors.size.should eq(1)
    errors.first.should start_with("disable_public_interface_for_the_kubernetes_api_load_balancer requires a multi-master cluster")
  end
end

describe Hetzner::LoadBalancer do
  it "never hands out the public address once the public interface is disabled" do
    lb = ApiLoadBalancerSpec.load_balancer(enabled: false)
    lb.ip_address(prefer_private: false).should eq("10.20.0.254")
    lb.ip_address(prefer_private: true).should eq("10.20.0.254")
  end

  it "treats a missing enabled field as an enabled public interface" do
    lb = Hetzner::LoadBalancer.from_json(%({"id": 1, "name": "x", "private_net": [], "public_net": {"ipv4": {"ip": "198.51.100.7"}}}))
    lb.public_interface_enabled?.should be_true
    lb.ip_address(prefer_private: false).should eq("198.51.100.7")
  end

  it "treats a load balancer without public_net as having no public interface" do
    lb = Hetzner::LoadBalancer.from_json(%({"id": 1, "name": "x", "private_net": [{"ip": "10.20.0.254"}]}))
    lb.public_interface_enabled?.should be_false
  end

  describe "#private_only_error" do
    it "accepts a load balancer on the network whose targets use private IPs" do
      ApiLoadBalancerSpec.load_balancer.private_only_error(ApiLoadBalancerSpec::NETWORK_ID).should be_nil
    end

    it "rejects a load balancer that is not attached to the configured network" do
      ApiLoadBalancerSpec.load_balancer(network: 7).private_only_error(ApiLoadBalancerSpec::NETWORK_ID).not_nil!.should contain("not attached to the configured private network")
    end

    it "rejects a target that uses a public IP" do
      ApiLoadBalancerSpec.load_balancer(use_private_ip: false).private_only_error(ApiLoadBalancerSpec::NETWORK_ID).not_nil!.should contain("targets that do not use private IPs")
    end

    it "still rejects a public target when the public interface is already disabled" do
      ApiLoadBalancerSpec.load_balancer(enabled: false, use_private_ip: false).private_only_error(ApiLoadBalancerSpec::NETWORK_ID).not_nil!.should contain("targets that do not use private IPs")
    end
  end
end

describe Hetzner::LoadBalancer::Create do
  it "rejects an already-private load balancer with a public-IP target without calling the API" do
    ApiLoadBalancerSpec.create(ApiLoadBalancerSpec.load_balancer_json(enabled: false, use_private_ip: false)) do |create, client|
      expect_raises(Exception, /targets that do not use private IPs/) { create.run }
      client.posts.should be_empty
    end
  end

  it "rejects an already-private load balancer that is not attached to the network" do
    ApiLoadBalancerSpec.create(ApiLoadBalancerSpec.load_balancer_json(network: 7, enabled: false)) do |create, client|
      expect_raises(Exception, /not attached to the configured private network/) { create.run }
      client.posts.should be_empty
    end
  end

  it "returns an already-private, valid load balancer untouched" do
    ApiLoadBalancerSpec.create(ApiLoadBalancerSpec.load_balancer_json(enabled: false)) do |create, client|
      create.run.not_nil!.id.should eq(1)
      client.posts.should be_empty
    end
  end
end
