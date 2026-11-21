require "../../../models/networking_config/cni"
require "../../../models/networking_config/private_network"
require "../../../models/networking_config/cni_config/cilium_mtu"

class Configuration::Validators::NetworkingConfig::CNIConfig::Cilium
  alias CiliumMTU = Configuration::Models::NetworkingConfig::CNIConfig::CiliumMTU

  getter errors : Array(String)
  getter cni : Configuration::Models::NetworkingConfig::CNI
  getter private_network : Configuration::Models::NetworkingConfig::PrivateNetwork
  getter dual_stack : Bool

  def initialize(@errors, @cni, @private_network, @dual_stack = false)
  end

  def validate
    if cilium.helm_values_path
      path = cilium.helm_values_path.not_nil!
      if !File.exists?(path)
        errors << "Cilium helm_values_path '#{path}' does not exist"
      elsif !File.file?(path)
        errors << "Cilium helm_values_path '#{path}' is not a file"
      end
    end

    if cilium.chart_version.nil? || cilium.chart_version.empty?
      errors << "Cilium chart_version is required"
    end

    validate_mtu
    validate_connectivity_check
  end

  private def cilium
    cni.cilium
  end

  private def validate_mtu
    mtu = cilium.mtu
    underlay_mtu = cilium.underlay_mtu
    helm_values_path = cilium.helm_values_path

    if mtu && mtu < 0
      errors << "Cilium mtu must be 0 (auto-detect) or a positive number of bytes, got #{mtu}"
      return
    end

    if mtu && mtu > 0 && mtu < CiliumMTU::MIN_UNDERLAY_MTU
      errors << "Cilium mtu must be 0 (auto-detect) or at least #{CiliumMTU::MIN_UNDERLAY_MTU} bytes, got #{mtu}"
      return
    end

    if underlay_mtu && underlay_mtu < CiliumMTU::MIN_UNDERLAY_MTU
      errors << "Cilium underlay_mtu must be at least #{CiliumMTU::MIN_UNDERLAY_MTU} bytes, got #{underlay_mtu}"
      return
    end

    if helm_values_path && CiliumMTU.explicit_mtu(mtu)
      errors << "Cilium mtu is ignored when helm_values_path is set; configure MTU in the Helm values file instead"
      return
    end

    mtu_settings = effective_mtu_settings
    return unless mtu_settings

    explicit_mtu = mtu_settings.explicit_mtu

    unless explicit_mtu
      if underlay_mtu
        errors << (helm_values_path ? "Cilium underlay_mtu is set but the Helm values file does not set a positive MTU" : "Cilium mtu must be set to a positive value when underlay_mtu is configured")
      end
      return
    end

    effective_underlay_mtu = underlay_mtu || CiliumMTU.default_underlay_mtu(private_network.enabled)
    underlay_source = underlay_mtu ? "underlay_mtu" : "default underlay MTU; set underlay_mtu if your network path differs"

    CiliumMTU.problems(explicit_mtu, effective_underlay_mtu, mtu_settings.overhead, underlay_source, CiliumMTU.min_pod_mtu(dual_stack)).each do |problem|
      errors << "Cilium #{problem}"
    end
  end

  # MTU settings Cilium will be installed with: those of the custom Helm values
  # file when one is used, otherwise those rendered from this configuration.
  private def effective_mtu_settings : CiliumMTU::Settings?
    helm_values_path = cilium.helm_values_path
    return CiliumMTU.settings_from_config(cni) unless helm_values_path
    return unless File.file?(helm_values_path)

    CiliumMTU.settings_from_helm_values(File.read(helm_values_path), cilium.chart_version)
  rescue ex : CiliumMTU::Error
    errors << "Cilium helm_values_path '#{helm_values_path}' could not be read for MTU validation: #{ex.message}"
    nil
  end

  private def validate_connectivity_check
    check = cilium.connectivity_check
    return unless check.enabled?

    errors << "Cilium connectivity_check.image must not be empty" if check.image.strip.empty?
    errors << "Cilium connectivity_check.timeout_seconds must be greater than 0" unless check.timeout_seconds > 0
  end
end
