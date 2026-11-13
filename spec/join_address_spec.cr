require "./routing_spec_helper"
require "../src/kubernetes/kubeconfig_manager"

module JoinAddressSpec
  def self.config(hostname : String? = nil, join_via_hostname = false)
    yaml = RoutingSpec.config
    extra = {} of String => String | Bool
    extra["api_server_hostname"] = hostname unless hostname.nil?
    extra["join_via_api_server_hostname"] = join_via_hostname
    yaml + extra.to_yaml.sub(/\A---\n/, "")
  end

  # Renders the worker script for a cloud pool (external: false) or the external pool.
  def self.k3s_url(loader, external = false) : String
    pool = loader.settings.worker_node_pools.first
    unless external
      pool.instance_type = "cpx22"
      pool.external = nil
    end
    script = RoutingSpec.worker_script(loader)
    script.match(/K3S_URL=(\S+) /).not_nil![1]
  end

  def self.tls_sans(loader) : String
    manager = Kubernetes::KubeconfigManager.new(loader, loader.settings, RoutingSpec::RecordingSSH.new("/nonexistent/test-key"))
    manager.generate_tls_sans([RoutingSpec.master], RoutingSpec.master, nil)
  end
end

describe "Worker join address" do
  it "joins through the first master's private IP when the flag is off" do
    RoutingSpec.with_loader(JoinAddressSpec.config(hostname: "k8s.example.com")) do |loader|
      JoinAddressSpec.k3s_url(loader).should eq("https://10.20.0.5:6443")
    end
  end

  it "joins through api_server_hostname when the flag is on" do
    RoutingSpec.with_loader(JoinAddressSpec.config(hostname: "k8s.example.com", join_via_hostname: true)) do |loader|
      JoinAddressSpec.k3s_url(loader).should eq("https://k8s.example.com:6443")
    end
  end

  it "keeps external nodes on the first master with the flag on" do
    RoutingSpec.with_loader(JoinAddressSpec.config(hostname: "k8s.example.com", join_via_hostname: true)) do |loader|
      JoinAddressSpec.k3s_url(loader, external: true).should eq("https://10.20.0.5:6443")
    end
  end

  it "falls back to the first master when the flag is on but no hostname is set" do
    RoutingSpec.with_loader(JoinAddressSpec.config(join_via_hostname: true)) do |loader|
      JoinAddressSpec.k3s_url(loader).should eq("https://10.20.0.5:6443")
    end
  end

  it "treats a blank hostname as unset" do
    RoutingSpec.with_loader(JoinAddressSpec.config(hostname: "   ", join_via_hostname: true)) do |loader|
      loader.settings.api_server_hostname.should be_nil
      JoinAddressSpec.k3s_url(loader).should eq("https://10.20.0.5:6443")
      JoinAddressSpec.tls_sans(loader).should_not contain("--tls-san= ")
    end
  end

  it "uses the same trimmed hostname for the join address and the masters' TLS SAN" do
    RoutingSpec.with_loader(JoinAddressSpec.config(hostname: "  k8s.example.com  ", join_via_hostname: true)) do |loader|
      loader.settings.api_server_hostname.should eq("k8s.example.com")
      JoinAddressSpec.k3s_url(loader).should eq("https://k8s.example.com:6443")
      sans = JoinAddressSpec.tls_sans(loader).split(" ")
      sans.should contain("--tls-san=k8s.example.com")
      sans.each { |san| san.should start_with("--tls-san=") }
    end
  end
end
