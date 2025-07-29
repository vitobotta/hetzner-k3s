require "./ciium"
require "./flannel"

class Configuration::NetworkingComponents::CNI
  include YAML::Serializable
  include YAML::Serializable::Unmapped

  getter enabled : Bool = true
  getter mode : String = "flannel"
  getter encryption : Bool = true
  getter cilium : Configuration::NetworkingComponents::Cilium = Configuration::NetworkingComponents::Cilium.new
  getter flannel : Configuration::NetworkingComponents::Flannel = Configuration::NetworkingComponents::Flannel.new
  getter cilium_egress_gateway : Bool = false

  def initialize
  end

  def validate(errors, private_network)
    return unless enabled

    errors << "CNI encryption must be enabled when private networking is disabled" unless encryption || private_network.enabled
    errors << "CNI mode must be either 'flannel' or 'cilium' when CNI is enabled" unless {"flannel", "cilium"}.includes?(mode)
    
    cilium.validate(errors) if cilium?
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
