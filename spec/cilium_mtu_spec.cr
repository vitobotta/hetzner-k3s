require "./routing_spec_helper"
require "../src/kubernetes/software/cilium"

private alias CiliumMTU = Configuration::Models::NetworkingConfig::CNIConfig::CiliumMTU

private class CiliumValuesProbe < Kubernetes::Software::Cilium
  def rendered : String
    generate_helm_values
  end

  def values : Hash(YAML::Any, YAML::Any)
    YAML.parse(rendered).as_h
  end
end

# Builds a config from the shared synthetic topology, then overrides the Cilium
# block with a raw YAML fragment so each example states exactly what it tests.
private def cilium_config(cilium_yaml : String? = nil,
                          encryption : Bool? = nil,
                          cluster_cidr : String? = nil,
                          private_network : Bool = true) : String
  document = YAML.parse(RoutingSpec.config(private_network: private_network)).as_h
  networking = document["networking"].as_h
  cni = networking["cni"].as_h

  cni[YAML::Any.new("encryption")] = YAML::Any.new(encryption.not_nil!) unless encryption.nil?
  networking[YAML::Any.new("cluster_cidr")] = YAML::Any.new(cluster_cidr.not_nil!) unless cluster_cidr.nil?
  cni[YAML::Any.new("cilium")] = YAML.parse(cilium_yaml.not_nil!) if cilium_yaml

  document.to_yaml
end

# Runs the CNI validator exactly as Configuration::Validators::Networking does,
# including its own dual stack detection.
private def mtu_errors(cilium_yaml : String? = nil,
                       encryption : Bool? = nil,
                       cluster_cidr : String? = nil,
                       private_network : Bool = true) : Array(String)
  errors = [] of String
  yaml = cilium_config(cilium_yaml, encryption, cluster_cidr, private_network)

  RoutingSpec.with_loader(yaml) do |loader|
    settings = loader.settings
    networking_validator = Configuration::Validators::Networking.new(
      errors,
      settings.networking,
      settings,
      Hetzner::Client.new(""),
      settings.networking.private_network
    )
    Configuration::Validators::NetworkingConfig::CNI.new(
      errors,
      settings.networking.cni,
      settings.networking.private_network,
      networking_validator.dual_stack?
    ).validate
  end

  errors
end

private def rendered_values(cilium_yaml : String? = nil, encryption : Bool? = nil) : String
  rendered = ""
  RoutingSpec.with_loader(cilium_config(cilium_yaml, encryption)) do |loader|
    rendered = CiliumValuesProbe.new(loader, loader.settings).rendered
  end
  rendered
end

private def helm_settings(content : String, chart_version : String? = nil) : CiliumMTU::Settings
  CiliumMTU.settings_from_helm_values(content, chart_version)
end

describe "Cilium MTU validation" do
  it "accepts a config that does not set an MTU" do
    mtu_errors.should eq([] of String)
  end

  it "accepts an MTU that fits the private network" do
    mtu_errors("mtu: 1450").should eq([] of String)
  end

  it "accepts an MTU of 0 as auto-detect" do
    mtu_errors("mtu: 0").should eq([] of String)
  end

  it "rejects an MTU larger than the network path" do
    mtu_errors("mtu: 1500").first.should contain("exceeds the network path MTU 1450")
  end

  it "uses 1500 as the path MTU without a private network" do
    mtu_errors("mtu: 1500", encryption: true, private_network: false).should eq([] of String)
  end

  it "rejects out of range and negative values" do
    mtu_errors("mtu: 1279").first.should contain("at least 1280")
    mtu_errors("mtu: -1").first.should contain("positive number of bytes")
  end

  it "rejects an underlay_mtu below the IPv6 minimum" do
    mtu_errors("mtu: 1300\nunderlay_mtu: 1200").first.should contain("underlay_mtu must be at least 1280")
  end

  it "rejects underlay_mtu on its own" do
    mtu_errors("underlay_mtu: 1450").first.should contain("must be set to a positive value")
  end

  it "rejects an MTU that leaves pods below 1230 after WireGuard" do
    mtu_errors("mtu: 1300", encryption: true).first.should contain("pod MTU must be at least 1230")
  end

  it "accepts an MTU that leaves pods exactly on the floor" do
    mtu_errors("mtu: 1370", encryption: true).should eq([] of String)
  end

  it "rejects the same MTU once Cilium raised the WireGuard overhead" do
    yaml = "mtu: 1370\nchart_version: v1.19.5"
    mtu_errors(yaml, encryption: true).first.should contain("pod MTU must be at least 1230")
  end

  it "accepts one more byte with the newer overhead" do
    yaml = "mtu: 1375\nchart_version: v1.19.5"
    mtu_errors(yaml, encryption: true).should eq([] of String)
  end

  it "rejects an MTU that is only safe on IPv4 when the pod network is dual stack" do
    yaml = "mtu: 1400"
    mtu_errors(yaml, encryption: true).should eq([] of String)
    mtu_errors(yaml, encryption: true, cluster_cidr: "fd00:10:244::/72").first.should contain("pod MTU must be at least 1280")
  end

  it "rejects mtu together with helm_values_path" do
    File.tempfile("cilium-values", ".yaml") do |file|
      file.print("MTU: 1450\n")
      file.flush

      errors = mtu_errors("mtu: 1450\nhelm_values_path: #{file.path}")
      errors.any?(&.includes?("mtu is ignored when helm_values_path is set")).should be_true
    end
  end

  it "validates connectivity_check settings only when the check is enabled" do
    mtu_errors("connectivity_check:\n    image: \"\"").first.should contain("image must not be empty")
    mtu_errors("connectivity_check:\n    timeout_seconds: 0").first.should contain("timeout_seconds must be greater than 0")
    mtu_errors("connectivity_check:\n    enabled: false\n    image: \"\"").should eq([] of String)
  end

  it "detects a dual stack pod network from either CIDR" do
    detected = [] of Bool
    [cilium_config, cilium_config(cluster_cidr: "fd00:10:244::/72")].each do |yaml|
      RoutingSpec.with_loader(yaml) do |loader|
        settings = loader.settings
        validator = Configuration::Validators::Networking.new(
          [] of String,
          settings.networking,
          settings,
          Hetzner::Client.new(""),
          settings.networking.private_network
        )
        detected << validator.dual_stack?
      end
    end

    detected.should eq([false, true])
    CiliumMTU.dual_stack?("10.244.0.0/16", "fd00:10:43::/112").should be_true
    CiliumMTU.dual_stack?("10.244.0.0/16", "10.43.0.0/16").should be_false
  end
end

describe "Cilium MTU from Helm values" do
  it "treats a missing, empty or comments only MTU as auto-detect" do
    helm_settings("").mtu.should be_nil
    helm_settings("# nothing here\n").mtu.should be_nil
    helm_settings("MTU: 0").pod_mtu.should be_nil
  end

  it "reads MTU in either case and as a quoted string" do
    helm_settings("MTU: 1450").mtu.should eq(1450)
    helm_settings("mtu: 1450").mtu.should eq(1450)
    helm_settings("MTU: '1450'").mtu.should eq(1450)
  end

  it "derives the pod MTU from the routing mode and encryption" do
    helm_settings("MTU: 1450").pod_mtu.should eq(1400)
    helm_settings("MTU: 1450\nroutingMode: native\n").pod_mtu.should eq(1450)
    helm_settings("MTU: 1450\nencryption:\n  enabled: true\n  type: ipsec\n").pod_mtu.should eq(1323)
  end

  it "uses the chart default encryption type when the file enables encryption without a type" do
    helm_settings("MTU: 1450\nencryption:\n  enabled: true\n").pod_mtu.should eq(1323)
  end

  it "follows the WireGuard overhead of the chart version" do
    helm_settings("MTU: 1450\nencryption:\n  enabled: true\n  type: wireguard\n", "v1.17.2").pod_mtu.should eq(1320)
    helm_settings("MTU: 1450\nencryption:\n  enabled: true\n  type: wireguard\n", "v1.19.5").pod_mtu.should eq(1305)
  end

  it "rejects a non integer MTU" do
    expect_raises(CiliumMTU::Error, /must be an integer/) do
      helm_settings("MTU: abc")
    end
  end
end

describe "Cilium MTU overhead" do
  it "keeps 80 bytes of WireGuard overhead up to Cilium v1.19.0" do
    ["v1.17.2", "1.18.0", "v1.19.0"].each do |version|
      CiliumMTU.wireguard_overhead(version).should eq(80)
    end
  end

  it "uses 95 bytes from Cilium v1.19.5" do
    ["v1.19.5", "v1.20.0", "v2.0.0"].each do |version|
      CiliumMTU.wireguard_overhead(version).should eq(95)
    end
  end

  it "falls back to the pinned chart value for an unknown version" do
    CiliumMTU.wireguard_overhead(nil).should eq(80)
    CiliumMTU.wireguard_overhead("").should eq(80)
    CiliumMTU.wireguard_overhead("main").should eq(80)
  end
end

describe "rendered Cilium values" do
  it "omits the MTU key and adds no blank line when no MTU is configured" do
    rendered = rendered_values
    rendered.should_not contain("MTU:")
    rendered.should contain("tunnelProtocol: vxlan\n\n# IPAM settings")
  end

  it "writes the configured MTU after the tunnel protocol" do
    values = YAML.parse(rendered_values("mtu: 1450")).as_h
    values["MTU"].as_i.should eq(1450)
  end

  it "treats an MTU of 0 as unset" do
    rendered_values("mtu: 0").should_not contain("MTU:")
  end
end
