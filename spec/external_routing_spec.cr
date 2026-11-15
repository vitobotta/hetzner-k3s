require "./routing_spec_helper"

describe "Externally routed private networks" do
  it "keeps the flag disabled by default" do
    Configuration::Models::NetworkingConfig::PrivateNetwork.new.external_routing.should be_false
  end

  it "accepts existing private-IP-only external workers without an ip field" do
    RoutingSpec.with_loader do |loader|
      RoutingSpec.errors(loader.settings).should be_empty
      loader.settings.worker_node_pools.first.external.not_nil!.nodes.first.cluster_ip.should eq("10.10.0.10")
    end
  end

  it "rejects routing without an external pool" do
    RoutingSpec.with_loader do |loader|
      loader.settings.worker_node_pools.clear
      RoutingSpec.errors(loader.settings).join.should contain("requires at least one external worker node pool")
    end
  end

  it "rejects routing when private networking is disabled" do
    RoutingSpec.with_loader(RoutingSpec.config(private_network: false)) do |loader|
      RoutingSpec.errors(loader.settings).join.should contain("requires networking.private_network.enabled")
    end
  end

  it "retains the private-network restriction without the opt-in" do
    RoutingSpec.with_loader(RoutingSpec.config(routing: false)) do |loader|
      RoutingSpec.errors(loader.settings).join.should contain("requires the private network to be disabled")
    end
  end

  it "retains the local-firewall requirement for public external workers" do
    yaml = RoutingSpec.config(private_network: false, routing: false).sub("use_local_firewall: true", "use_local_firewall: false")
    RoutingSpec.with_loader(yaml) do |loader|
      RoutingSpec.errors(loader.settings).join.should contain("requires the local firewall")
    end
  end

  it "rejects an explicit ip outside routed mode" do
    RoutingSpec.with_loader(RoutingSpec.config(private_network: false, routing: false, ip: "10.10.0.10")) do |loader|
      RoutingSpec.errors(loader.settings).join.should contain("may only set external.nodes[].ip")
    end
  end

  ["", "node.example", "10.10.0.999", "10.10.0.10/24", "2001:db8::10", "10.10.0.10\n", "$(touch /tmp/invalid)", "10.10.0.10;true"].each do |ip|
    it "rejects invalid or non-literal node ip #{ip.inspect}" do
      RoutingSpec.with_loader(RoutingSpec.config(ip: ip)) do |loader|
        RoutingSpec.errors(loader.settings).join.should contain("invalid cluster IP")
      end
    end
  end

  it "rejects a DNS host even when ip is supplied" do
    RoutingSpec.with_loader(RoutingSpec.config(host: "node.example", ip: "10.10.0.10")) do |loader|
      RoutingSpec.errors(loader.settings).join.should contain("invalid host")
    end
  end

  it "rejects duplicate effective IPs within a pool, including a host fallback" do
    RoutingSpec.with_loader do |loader|
      pool = loader.settings.worker_node_pools.first
      node = Configuration::Models::ExternalNode.from_yaml(pool.external.not_nil!.nodes.first.to_yaml)
      node.host = "192.0.2.11"
      node.ip = "10.10.0.10"
      node.index = 2
      pool.instance_count = 2
      pool.external.not_nil!.nodes << node
      RoutingSpec.errors(loader.settings).join.should contain("duplicate cluster IPs")
    end
  end

  it "rejects duplicate effective IPs across pools" do
    RoutingSpec.with_loader do |loader|
      pool = Configuration::Models::WorkerNodePool.from_yaml(loader.settings.worker_node_pools.first.to_yaml)
      pool.name = "other-workers"
      pool.external.not_nil!.nodes.first.host = "192.0.2.11"
      pool.external.not_nil!.nodes.first.ip = "10.10.0.10"
      loader.settings.worker_node_pools << pool
      RoutingSpec.errors(loader.settings).join.should contain("reuses cluster IPs")
    end
  end

  ["cilium", "flannel"].each do |cni|
    ["192.0.2.5 10.20.0.5", "10.20.0.5"].each do |host_ips|
      it "preserves cloud-master private addressing with #{cni} and addresses #{host_ips}" do
        RoutingSpec.with_loader(RoutingSpec.config(cni: cni)) do |loader|
          result = RoutingSpec.install(RoutingSpec.master_script(loader), host_ips)
          result[:success].should be_true
          result[:args].should contain("--node-ip=10.20.0.5")
          result[:args].should contain("--advertise-address=10.20.0.5")
          if cni == "flannel"
            result[:args].should contain("--flannel-iface=enp7s0")
          else
            result[:args].should contain("--flannel-backend=none")
            result[:args].any?(&.starts_with?("--flannel-iface=")).should be_false
          end
        end
      end
    end

    it "uses a configured routed #{cni} address even when hostname lists a public IP first" do
      RoutingSpec.with_loader(RoutingSpec.config(cni: cni)) do |loader|
        result = RoutingSpec.install(RoutingSpec.worker_script(loader))
        result[:success].should be_true
        result[:args].should contain("--node-ip=10.10.0.10")
        result[:args].should contain("--kubelet-arg=provider-id=external://10.10.0.10")
        result[:args].any?(&.starts_with?("--node-external-ip=")).should be_false
        result[:args].any?(&.includes?("cloud-provider=external")).should be_false
        if cni == "flannel"
          result[:args].should contain("--flannel-iface=vpn0")
        else
          result[:args].any?(&.starts_with?("--flannel-iface=")).should be_false
        end
      end
    end
  end

  it "advertises a distinct configured SSH endpoint, not hostname's first address" do
    RoutingSpec.with_loader(RoutingSpec.config(host: "192.0.2.99", ip: "10.10.0.10")) do |loader|
      RoutingSpec.errors(loader.settings).should be_empty
      result = RoutingSpec.install(RoutingSpec.worker_script(loader))
      result[:success].should be_true
      result[:args].should contain("--node-ip=10.10.0.10")
      result[:args].should contain("--node-external-ip=192.0.2.99")
      result[:args].should_not contain("--node-external-ip=192.0.2.10")
    end
  end

  it "fails before installation when the routed IP is not local" do
    RoutingSpec.with_loader(RoutingSpec.config(ip: "10.10.0.99")) do |loader|
      result = RoutingSpec.install(RoutingSpec.worker_script(loader))
      result[:success].should be_false
      result[:args].should be_empty
      result[:output].should contain("not assigned to a local interface")
    end
  end

  it "keeps cloud-worker private-interface detection with the flag enabled" do
    RoutingSpec.with_loader do |loader|
      pool = loader.settings.worker_node_pools.first
      pool.instance_type = "cpx22"
      pool.external = nil
      result = RoutingSpec.install(RoutingSpec.worker_script(loader), "192.0.2.5 10.20.0.5")
      result[:success].should be_true
      result[:args].should contain("--node-ip=10.20.0.5")
      result[:args].should contain("--node-external-ip=192.0.2.5")
      result[:args].should contain("--flannel-iface=enp7s0")
    end
  end

  it "preserves public-mode worker addressing and provider identity" do
    RoutingSpec.with_loader(RoutingSpec.config(private_network: false, routing: false, host: "192.0.2.10")) do |loader|
      RoutingSpec.errors(loader.settings).should be_empty
      result = RoutingSpec.install(RoutingSpec.worker_script(loader))
      result[:success].should be_true
      result[:args].should contain("--node-ip=192.0.2.10")
      result[:args].should contain("--node-external-ip=192.0.2.10")
      result[:args].should contain("--kubelet-arg=provider-id=external://192.0.2.10")
      result[:args].any?(&.starts_with?("--flannel-iface=")).should be_false
    end
  end

  it "preserves Robot provider identity and cloud-controller initialization" do
    RoutingSpec.with_loader(RoutingSpec.config(host: "192.0.2.10", ip: "10.10.0.10")) do |loader|
      pool = loader.settings.worker_node_pools.first
      external = pool.external.not_nil!
      external.provider = "robot"
      external.nodes.first.robot_server_number = 123
      result = RoutingSpec.install(RoutingSpec.worker_script(loader))
      result[:success].should be_true
      result[:args].should contain("--kubelet-arg=provider-id=hrobot://123")
      result[:args].should contain("cloud-provider=external")
    end
  end

  ["", "192.0.2.10"].each do |external_ip|
    it "runs via the configured SSH host when InternalIP differs and ExternalIP is #{external_ip.inspect}" do
      RoutingSpec.with_loader(RoutingSpec.config(host: "192.0.2.99", ip: "10.10.0.10")) do |loader|
        instance = Hetzner::Instance.new(0, "running", "custom-hostname", "10.10.0.10", external_ip)
        ssh, target, port, use_agent, use_sudo = RoutingSpec::Run.new(loader).ssh_target(instance)
        target.host_ip_address.should eq("192.0.2.99")
        target.name.should eq("custom-hostname")
        ssh.user.should eq("operator")
        ssh.private_ssh_key_path.should eq("/nonexistent/test-key")
        port.should eq(2222)
        use_agent.should be_false
        use_sudo.should be_true
        instance.private_ip_address.should eq("10.10.0.10")
      end
    end
  end

  it "retains cloud SSH target selection" do
    RoutingSpec.with_loader do |loader|
      _, target, _, _, _ = RoutingSpec::Run.new(loader).ssh_target(RoutingSpec.master)
      target.host_ip_address.should eq("192.0.2.5")
    end
  end

  it "preserves master and cloud-worker arguments when routing is toggled" do
    ["cilium", "flannel"].each do |cni|
      master_args = [] of Array(String)
      worker_args = [] of Array(String)
      [false, true].each do |routing|
        RoutingSpec.with_loader(RoutingSpec.config(routing: routing, cni: cni)) do |loader|
          pool = loader.settings.worker_node_pools.first
          pool.instance_type = "cpx22"
          pool.external = nil
          master = RoutingSpec.install(RoutingSpec.master_script(loader), "192.0.2.5 10.20.0.5")
          worker = RoutingSpec.install(RoutingSpec.worker_script(loader), "192.0.2.5 10.20.0.5")
          master[:success].should be_true
          worker[:success].should be_true
          master_args << master[:args]
          worker_args << worker[:args]
        end
      end
      master_args[0].should eq(master_args[1])
      worker_args[0].should eq(worker_args[1])
    end
  end

  it "preserves public-only cloud-master addressing" do
    RoutingSpec.with_loader(RoutingSpec.config(private_network: false, routing: false)) do |loader|
      result = RoutingSpec.install(RoutingSpec.master_script(loader), "192.0.2.5")
      result[:success].should be_true
      result[:args].should contain("--advertise-address=192.0.2.5")
      result[:args].should contain("--node-ip=192.0.2.5")
      result[:args].should contain("--node-external-ip=192.0.2.5")
      result[:args].should contain("--kubelet-arg=provider-id=hcloud://123")
    end
  end

  it "does not add Flannel arguments when the CNI is disabled" do
    yaml = RoutingSpec.config(cni: "flannel").sub("cni:\n    enabled: true", "cni:\n    enabled: false")
    RoutingSpec.with_loader(yaml) do |loader|
      loader.settings.networking.cni.enabled.should be_false
      result = RoutingSpec.install(RoutingSpec.worker_script(loader))
      result[:success].should be_true
      result[:args].any?(&.starts_with?("--flannel-iface=")).should be_false
    end
  end

  it "does not deploy a local firewall in routed mode even if use_local_firewall is true" do
    yaml = RoutingSpec.config.sub("use_local_firewall: false", "use_local_firewall: true")
    RoutingSpec.with_loader(yaml) do |loader|
      loader.settings.networking.public_network.use_local_firewall.should be_true
      ssh = RoutingSpec::RecordingSSH.new("/nonexistent/test-key")
      Kubernetes::LocalFirewall::Setup.new(loader.settings, ssh).deploy_with_ssh(RoutingSpec.master, ssh, 2222)
      ssh.commands.should be_empty
    end
  end

  it "still deploys the local firewall in public external mode" do
    RoutingSpec.with_loader(RoutingSpec.config(private_network: false, routing: false)) do |loader|
      ssh = RoutingSpec::RecordingSSH.new("/nonexistent/test-key")
      Kubernetes::LocalFirewall::Setup.new(loader.settings, ssh).deploy_with_ssh(RoutingSpec.master, ssh, 2222)
      ssh.commands.size.should eq(2)
      ssh.commands.last.should contain("systemctl restart firewall.service")
    end
  end

  it "retains public-mode per-node SSH credentials and generated-name matching" do
    RoutingSpec.with_loader(RoutingSpec.config(private_network: false, routing: false, host: "192.0.2.99")) do |loader|
      pool = loader.settings.worker_node_pools.first
      pool.external.not_nil!.nodes.first.manage_hostname = true
      name = loader.settings.external_worker_hostname(pool, 1)
      instance = Hetzner::Instance.new(0, "running", name, "10.10.0.10", "192.0.2.10")
      ssh, target, port, _, _ = RoutingSpec::Run.new(loader).ssh_target(instance)
      target.host_ip_address.should eq("192.0.2.99")
      ssh.user.should eq("operator")
      port.should eq(2222)
    end
  end

  it "prefers InternalIP identity over another worker's SSH endpoint" do
    RoutingSpec.with_loader(RoutingSpec.config(host: "192.0.2.99", ip: "10.10.0.10")) do |loader|
      pool = loader.settings.worker_node_pools.first
      other = Configuration::Models::ExternalNode.from_yaml(pool.external.not_nil!.nodes.first.to_yaml)
      other.host = "10.10.0.10"
      other.ip = "10.10.0.11"
      other.index = 2
      pool.external.not_nil!.nodes << other
      instance = Hetzner::Instance.new(0, "running", "custom-hostname", "10.10.0.10", "")
      _, target, _, _, _ = RoutingSpec::Run.new(loader).ssh_target(instance)
      target.host_ip_address.should eq("192.0.2.99")
    end
  end
end
