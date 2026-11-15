require "./routing_spec_helper"

private def instance_json(ipv4 : String? = nil, ipv6 : String? = nil, private_ip : String? = nil)
  public_net = {"ipv4" => ipv4 ? {"ip" => ipv4} : nil, "ipv6" => ipv6 ? {"ip" => ipv6, "blocked" => false, "id" => 1} : nil}
  private_net = private_ip ? [{"ip" => private_ip, "alias_ips" => [] of String, "mac_address" => "aa:bb", "network" => 1}] : nil

  {
    "id"          => 1,
    "name"        => "test-master1",
    "status"      => "running",
    "public_net"  => public_net,
    "private_net" => private_net,
  }.to_json
end

private def instance(ipv4 : String? = nil, ipv6 : String? = nil, private_ip : String? = nil)
  Hetzner::Instance.from_json(instance_json(ipv4, ipv6, private_ip))
end

private def public_network_errors(ipv4 : Bool, ipv6 : Bool, private_network : Bool = true, use_private_ip : Bool = false)
  errors = [] of String
  settings = Configuration::Main.from_yaml(
    RoutingSpec.config.sub("networking:\n", "networking:\n  ssh:\n    use_private_ip: #{use_private_ip}\n  private_network:\n    enabled: #{private_network}\n")
      .sub("  public_network:\n", "  public_network:\n    ipv4: #{ipv4}\n    ipv6: #{ipv6}\n")
  )

  Configuration::Validators::NetworkingConfig::PublicNetwork.new(errors, settings.networking.public_network, settings).validate
  errors
end

describe Hetzner::Instance do
  it "reads the public IPv6 address" do
    instance(ipv6: "2a01:4f8::1").public_ipv6_address.should eq("2a01:4f8::1")
  end

  it "connects over IPv6 when public IPv4 is disabled" do
    instance(ipv6: "2a01:4f8::1", private_ip: "10.0.0.2").host_ip_address.should eq("2a01:4f8::1")
  end

  it "keeps preferring IPv4 when it exists" do
    instance(ipv4: "192.0.2.10", ipv6: "2a01:4f8::1", private_ip: "10.0.0.2").host_ip_address.should eq("192.0.2.10")
  end

  it "still prefers the private address when asked to" do
    instance(ipv4: "192.0.2.10", ipv6: "2a01:4f8::1", private_ip: "10.0.0.2").host_ip_address(prefer_private_ip: true).should eq("10.0.0.2")
  end

  it "falls back to the private address without a public one" do
    instance(private_ip: "10.0.0.2").host_ip_address.should eq("10.0.0.2")
  end

  it "falls back to IPv6 when no public IPv4 is assigned" do
    instance(ipv6: "2a01:4f8::1").private_ip_address.should eq("2a01:4f8::1")
  end
end

describe Kubernetes::DeploymentHelper do
  it "uses the public IPv6 address for the API server without a public IPv4" do
    Kubernetes::DeploymentHelper.api_server_ip_address(instance(ipv6: "2a01:4f8::1")).should eq("2a01:4f8::1")
  end
end

describe Configuration::Validators::NetworkingConfig::PublicNetwork do
  it "accepts IPv6 with IPv4 disabled" do
    public_network_errors(ipv4: false, ipv6: true).should be_empty
  end

  it "rejects disabling both families" do
    errors = public_network_errors(ipv4: false, ipv6: false, use_private_ip: true)

    errors.should contain("networking.public_network.ipv4 and networking.public_network.ipv6 are both false, so no public address is left to connect to")
  end

  it "asks for use_private_ip when both families are disabled" do
    errors = public_network_errors(ipv4: false, ipv6: false, use_private_ip: true)
    errors.size.should eq(1)

    public_network_errors(ipv4: false, ipv6: false).size.should eq(2)
  end
end
