require "./routing_spec_helper"
require "../src/kubernetes/software/cilium"

# `false || true` is true in Crystal, so the three Hubble toggles used to ignore an explicit false.
private class CiliumValuesProbe < Kubernetes::Software::Cilium
  def values : Hash(YAML::Any, YAML::Any)
    YAML.parse(generate_helm_values).as_h
  end
end

private def values_for(yaml : String) : Hash(YAML::Any, YAML::Any)
  result = uninitialized CiliumValuesProbe

  RoutingSpec.with_loader(yaml) do |loader|
    result = CiliumValuesProbe.new(loader, loader.settings)
  end

  result.values
end

private def cilium_config(hubble : Bool? = nil, relay : Bool? = nil, ui : Bool? = nil) : String
  document = YAML.parse(RoutingSpec.config).as_h
  cilium = {} of YAML::Any => YAML::Any

  cilium[YAML::Any.new("hubble_enabled")] = YAML::Any.new(hubble.not_nil!) unless hubble.nil?
  cilium[YAML::Any.new("hubble_relay_enabled")] = YAML::Any.new(relay.not_nil!) unless relay.nil?
  cilium[YAML::Any.new("hubble_ui_enabled")] = YAML::Any.new(ui.not_nil!) unless ui.nil?

  cni = document["networking"].as_h["cni"].as_h
  cni[YAML::Any.new("cilium")] = YAML::Any.new(cilium)

  document.to_yaml
end

private def hubble_settings(values : Hash(YAML::Any, YAML::Any)) : Tuple(Bool, Bool, Bool)
  hubble = values["hubble"]
  {hubble["enabled"].as_bool, hubble["relay"]["enabled"].as_bool, hubble["ui"]["enabled"].as_bool}
end

describe "cilium hubble values" do
  it "keeps all three on when nothing is set" do
    hubble_settings(values_for(cilium_config)).should eq({true, true, true})
  end

  it "honours an explicit false for all three" do
    yaml = cilium_config(false, false, false)

    hubble_settings(values_for(yaml)).should eq({false, false, false})
  end

  it "turns relay and ui off with hubble, which they depend on" do
    hubble_settings(values_for(cilium_config(false))).should eq({false, false, false})
  end

  it "still honours an explicit true against that cascade" do
    yaml = cilium_config(false, true)

    hubble_settings(values_for(yaml)).should eq({false, true, false})
  end

  it "honours a single false" do
    hubble_settings(values_for(cilium_config(relay: false))).should eq({true, false, true})
  end
end
