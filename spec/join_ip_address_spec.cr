require "./routing_spec_helper"
require "../src/kubernetes/kubeconfig_manager"

module JoinIpAddressSpec
  FIRST_MASTER_PRIVATE_IP = "10.20.0.5"
  LB_PUBLIC_IP            = "198.51.100.7"
  LB_PRIVATE_IP           = "10.20.0.254"

  def self.load_balancer
    Hetzner::LoadBalancer.from_json(%({
      "id": 1,
      "name": "routing-test-api",
      "private_net": [{"ip": "#{LB_PRIVATE_IP}"}],
      "public_net": {"ipv4": {"ip": "#{LB_PUBLIC_IP}"}}
    }))
  end

  # A master the API describes the way it describes an IPv6-only server: the /64 network only.
  def self.ipv6_master(ipv4 : String? = nil)
    public_net = {"ipv6" => {"ip" => "2a01:4f8:c17:3333::/64"}}
    public_net["ipv4"] = {"ip" => ipv4} if ipv4
    Hetzner::Instance.from_json({"id" => 9, "name" => "routing-test-master1", "status" => "running", "public_net" => public_net}.to_json)
  end

  def self.ipv6_config : String
    RoutingSpec.config.sub("  public_network:\n", "  public_network:\n    ipv4: false\n")
  end

  def self.config(use_private_ip = false)
    RoutingSpec.config
      .sub("networking:\n", "networking:\n  ssh:\n    use_private_ip: #{use_private_ip}\n")
      .+("create_load_balancer_for_the_kubernetes_api: true\n")
  end

  # K3S_URL of the rendered worker script, for a cloud pool unless external is set.
  def self.k3s_url(loader, load_balancer, external = false) : String
    pool = loader.settings.worker_node_pools.first
    unless external
      pool.instance_type = "cpx22"
      pool.external = nil
    end
    generator = RoutingSpec::WorkerGenerator.new(loader, loader.settings, load_balancer)
    script = generator.generate_script([RoutingSpec.master], RoutingSpec.master, pool, pool.external.try(&.nodes.first?))
    script.match(/K3S_URL=(\S+) /).not_nil![1]
  end

  def self.tls_sans(loader, load_balancer, master = RoutingSpec.master) : Array(String)
    manager = Kubernetes::KubeconfigManager.new(loader, loader.settings, RoutingSpec::RecordingSSH.new("/nonexistent/test-key"))
    manager.generate_tls_sans([master], master, load_balancer).split(" ")
  end

  def self.k3s_url_for(loader, master) : String
    pool = loader.settings.worker_node_pools.first
    pool.instance_type = "cpx22"
    pool.external = nil
    generator = RoutingSpec::WorkerGenerator.new(loader, loader.settings, nil)
    script = generator.generate_script(master, master, pool, nil)
    script.match(/K3S_URL=(\S+) /).not_nil![1]
  end
end

describe Kubernetes::DeploymentHelper do
  master = RoutingSpec.master

  it "returns the load balancer's public IP when use_private_ip is false" do
    Kubernetes::DeploymentHelper.join_ip_address(master, JoinIpAddressSpec.load_balancer, false).should eq(JoinIpAddressSpec::LB_PUBLIC_IP)
  end

  it "returns the load balancer's private IP when use_private_ip is true" do
    Kubernetes::DeploymentHelper.join_ip_address(master, JoinIpAddressSpec.load_balancer, true).should eq(JoinIpAddressSpec::LB_PRIVATE_IP)
  end

  it "returns the first master's address when there is no load balancer" do
    [false, true].each do |use_private_ip|
      Kubernetes::DeploymentHelper.join_ip_address(master, nil, use_private_ip).should eq(JoinIpAddressSpec::FIRST_MASTER_PRIVATE_IP)
    end
  end
end

describe "Worker join through the API load balancer" do
  [false, true].each do |use_private_ip|
    it "joins the address the masters' TLS SANs carry (use_private_ip: #{use_private_ip})" do
      RoutingSpec.with_loader(JoinIpAddressSpec.config(use_private_ip)) do |loader|
        lb = JoinIpAddressSpec.load_balancer
        expected = use_private_ip ? JoinIpAddressSpec::LB_PRIVATE_IP : JoinIpAddressSpec::LB_PUBLIC_IP
        JoinIpAddressSpec.k3s_url(loader, lb).should eq("https://#{expected}:6443")
        JoinIpAddressSpec.tls_sans(loader, lb).should contain("--tls-san=#{expected}")
      end
    end
  end

  it "keeps external nodes on the first master when a load balancer exists" do
    RoutingSpec.with_loader(JoinIpAddressSpec.config) do |loader|
      JoinIpAddressSpec.k3s_url(loader, JoinIpAddressSpec.load_balancer, external: true).should eq("https://#{JoinIpAddressSpec::FIRST_MASTER_PRIVATE_IP}:6443")
    end
  end

  it "keeps workers on the first master without a load balancer" do
    RoutingSpec.with_loader(RoutingSpec.config) do |loader|
      JoinIpAddressSpec.k3s_url(loader, nil).should eq("https://#{JoinIpAddressSpec::FIRST_MASTER_PRIVATE_IP}:6443")
    end
  end
end

describe "IPv6 only clusters" do
  it "brackets the node address in the worker join URL" do
    RoutingSpec.with_loader(JoinIpAddressSpec.ipv6_config) do |loader|
      JoinIpAddressSpec.k3s_url_for(loader, JoinIpAddressSpec.ipv6_master).should eq("https://[2a01:4f8:c17:3333::1]:6443")
    end
  end

  # Adding an IPv6 SAN to a dual-stack cluster rewrites the k3s unit, which restarts the masters and
  # costs etcd quorum. It is only rendered where there is no public IPv4 to serve on.
  it "adds no IPv6 SAN to a dual-stack cluster" do
    RoutingSpec.with_loader(JoinIpAddressSpec.config) do |loader|
      sans = JoinIpAddressSpec.tls_sans(loader, nil, JoinIpAddressSpec.ipv6_master(ipv4: "192.0.2.10"))

      sans.any?(&.includes?("2a01:4f8")).should be_false
      sans.should contain("--tls-san=192.0.2.10")
    end
  end

  it "serves the certificate on the node address when IPv4 is disabled" do
    RoutingSpec.with_loader(JoinIpAddressSpec.ipv6_config) do |loader|
      sans = JoinIpAddressSpec.tls_sans(loader, nil, JoinIpAddressSpec.ipv6_master)

      sans.should contain("--tls-san=2a01:4f8:c17:3333::1")
      sans.any?(&.ends_with?("/64")).should be_false
    end
  end
end
