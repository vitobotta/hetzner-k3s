require "../../models/networking_config/cni_config/cilium"
require "../../models/networking_config/cni_config/flannel"
require "../../validators/networking/cni_config/cilium"

class Configuration::Validators::Networking::CNI
  getter errors : Array(String)
  getter cni : Configuration::Models::NetworkingConfig::CNI
  getter private_network : Configuration::Models::NetworkingConfig::PrivateNetwork

  def initialize(@errors, @cni, @private_network)
  end

  def validate
    return unless cni.enabled

    errors << "CNI encryption must be enabled when private networking is disabled" unless cni.encryption || private_network.enabled
    errors << "CNI mode must be either 'flannel' or 'cilium' when CNI is enabled" unless {"flannel", "cilium"}.includes?(cni.mode)

    Configuration::Validators::Networking::CNIConfig::Cilium.new(errors, cni.cilium).validate if cni.cilium?
  end
end