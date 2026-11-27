require "./routing_spec_helper"

# kube-proxy runs as a component of every node in the cluster, so kube_proxy_args has to reach the
# k3s agent on workers as well as the k3s server on masters. Like the masters, the workers leave it
# out when kube-proxy does not run (Cilium, or flannel.disable_kube_proxy): k3s would only ignore
# the flag there, and leaving it out keeps the worker script of such a cluster unchanged.
private def kube_proxy_config(mode = "flannel", disable_kube_proxy : Bool? = nil, args = ["proxy-mode=nftables"]) : String
  document = YAML.parse(RoutingSpec.config(cni: mode)).as_h
  document[YAML::Any.new("kube_proxy_args")] = YAML.parse(args.to_yaml)

  unless disable_kube_proxy.nil?
    cni = document["networking"].as_h["cni"].as_h
    cni[YAML::Any.new("flannel")] = YAML.parse({"disable_kube_proxy" => disable_kube_proxy}.to_yaml)
  end

  document.to_yaml
end

# The installer stub records each argument it receives on its own line, so a flag and its value are
# adjacent entries. Reading the values back proves the quotes around the rendered argument survived
# the shell.
private def installed_kube_proxy_args(script : String) : Array(String)
  result = RoutingSpec.install(script)
  result[:args].each_cons(2).select { |pair| pair[0] == "--kube-proxy-arg" }.map { |pair| pair[1] }.to_a
end

describe "kube_proxy_args" do
  it "reaches the k3s agent on workers" do
    RoutingSpec.with_loader(kube_proxy_config) do |loader|
      script = RoutingSpec.worker_script(loader)

      script.should contain(%(--kube-proxy-arg "proxy-mode=nftables"))
      installed_kube_proxy_args(script).should eq(["proxy-mode=nftables"])
    end
  end

  # RoutingSpec.config has a single external pool, so the example above renders the external node
  # path. Static cloud pools and autoscaled pools go through the same generator and need the flag too.
  it "reaches the k3s agent of static and autoscaled cloud pools" do
    document = YAML.parse(kube_proxy_config).as_h
    pools = document["worker_node_pools"].as_a
    pools << YAML.parse({"name" => "static", "instance_type" => "cpx22", "instance_count" => 1, "location" => "nbg1"}.to_yaml)
    pools << YAML.parse({"name" => "autoscaled", "instance_type" => "cpx22", "location" => "nbg1", "autoscaling" => {"enabled" => true, "min_instances" => 0, "max_instances" => 3}}.to_yaml)

    RoutingSpec.with_loader(document.to_yaml) do |loader|
      generator = RoutingSpec::WorkerGenerator.new(loader, loader.settings)
      cloud_pools = loader.settings.worker_node_pools.reject(&.external?)
      cloud_pools.map(&.name).should eq(["static", "autoscaled"])

      cloud_pools.each do |pool|
        script = generator.generate_script([RoutingSpec.master], RoutingSpec.master, pool)

        script.should contain(%(--kube-proxy-arg "proxy-mode=nftables"))
        installed_kube_proxy_args(script).should eq(["proxy-mode=nftables"])
      end
    end
  end

  it "keeps reaching the k3s server on masters" do
    RoutingSpec.with_loader(kube_proxy_config) do |loader|
      RoutingSpec.master_script(loader).should contain(%(--kube-proxy-arg "proxy-mode=nftables"))
    end
  end

  it "is left out of the worker script in Cilium mode, where kube-proxy does not run" do
    RoutingSpec.with_loader(kube_proxy_config(mode: "cilium")) do |loader|
      script = RoutingSpec.worker_script(loader)

      script.should_not contain("--kube-proxy-arg")
      installed_kube_proxy_args(script).should be_empty
    end
  end

  it "is left out of the worker script when flannel disables kube-proxy" do
    RoutingSpec.with_loader(kube_proxy_config(disable_kube_proxy: true)) do |loader|
      script = RoutingSpec.worker_script(loader)

      script.should_not contain("--kube-proxy-arg")
      installed_kube_proxy_args(script).should be_empty
    end
  end

  it "inserts nothing but the argument itself when the key is set" do
    with_flag = ""
    without_flag = ""
    RoutingSpec.with_loader(kube_proxy_config) { |loader| with_flag = RoutingSpec.worker_script(loader) }
    RoutingSpec.with_loader(kube_proxy_config(args: [] of String)) { |loader| without_flag = RoutingSpec.worker_script(loader) }

    with_flag.sub(%( --kube-proxy-arg "proxy-mode=nftables" ), "").should eq(without_flag)
  end

  it "leaves the worker script byte identical for a cluster that never sets the key" do
    # The rendered worker script is hashed into the cluster autoscaler's config checksum, so a
    # placeholder that adds its own space would roll that deployment on every cluster with an
    # autoscaling pool. Adjacent placeholders are what keeps the unset rendering unchanged.
    Kubernetes::Script::WorkerGenerator::WORKER_INSTALL_SCRIPT
      .should contain("{{ labels_and_taints }}{{ kube_proxy_args }}")
  end
end
