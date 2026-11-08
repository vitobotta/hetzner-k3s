require "spec"
require "yaml"
require "../src/configuration/loader"
require "../src/kubernetes/software/cilium"

class Kubernetes::Software::Cilium
  def rendered_helm_values_for_spec
    generate_helm_values
  end
end

module CiliumValuesSpec
  def self.config(cilium : Hash(String, Bool)? = nil)
    cni = {"enabled" => true, "mode" => "cilium", "encryption" => false} of String => Bool | String | Hash(String, Bool)
    cni["cilium"] = cilium unless cilium.nil?
    {
      "config_format_version" => 1,
      "hetzner_token"         => "",
      "cluster_name"          => "cilium-values-test",
      "kubeconfig_path"       => "/nonexistent/kubeconfig",
      "k3s_version"           => "v1.35.0+k3s1",
      "networking"            => {"cni" => cni},
      "masters_pool"          => {"instance_type" => "cpx22", "instance_count" => 1, "locations" => ["fsn1"]},
    }.to_yaml
  end

  def self.hubble(cilium : Hash(String, Bool)? = nil)
    File.tempfile("cilium-values-spec", ".yaml") do |file|
      file.print(config(cilium))
      file.flush
      loader = Configuration::Loader.new(file.path, nil, false)
      values = YAML.parse(Kubernetes::Software::Cilium.new(loader, loader.settings).rendered_helm_values_for_spec)
      return {
        values["hubble"]["enabled"].as_bool,
        values["hubble"]["relay"]["enabled"].as_bool,
        values["hubble"]["ui"]["enabled"].as_bool,
      }
    end
    raise "unreachable"
  end
end

describe Kubernetes::Software::Cilium do
  it "enables Hubble, Relay and UI when the options are not set" do
    CiliumValuesSpec.hubble.should eq({true, true, true})
  end

  it "disables Hubble, Relay and UI when the options are set to false" do
    CiliumValuesSpec.hubble({
      "hubble_enabled"       => false,
      "hubble_relay_enabled" => false,
      "hubble_ui_enabled"    => false,
    }).should eq({false, false, false})
  end

  it "honours each option independently" do
    CiliumValuesSpec.hubble({
      "hubble_enabled"       => true,
      "hubble_relay_enabled" => false,
      "hubble_ui_enabled"    => true,
    }).should eq({true, false, true})
  end
end
