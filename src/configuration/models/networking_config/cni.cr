require "./cni_config/cilium"
require "./cni_config/flannel"

class Configuration::Models::NetworkingConfig::CNI
  include YAML::Serializable
  include YAML::Serializable::Unmapped

  getter enabled : Bool = true
  getter mode : String = "flannel"
  getter encryption : Bool = true
  getter cilium : Configuration::Models::NetworkingConfig::CNIConfig::Cilium = Configuration::Models::NetworkingConfig::CNIConfig::Cilium.new
  getter flannel : Configuration::Models::NetworkingConfig::CNIConfig::Flannel = Configuration::Models::NetworkingConfig::CNIConfig::Flannel.new
  getter cilium_egress_gateway : Bool = false

  def initialize
  end

  def flannel?
    enabled? && mode == "flannel"
  end

  def cilium?
    enabled && mode == "cilium"
  end

  def encryption?
    encryption
  end

  def enabled?
    enabled
  end

  def kube_proxy?
    cilium? ? false : !flannel.disable_kube_proxy?
  end
end
