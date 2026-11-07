require "../../../models/networking_config/private_network"

class Configuration::Validators::NetworkingConfig::CNIConfig::Cilium
  VXLAN_OVERHEAD_BYTES       =   50
  MIN_UNDERLAY_MTU           = 1280
  MIN_LARGE_PACKET_POD_MTU   = 1230
  HETZNER_PRIVATE_NETWORK_MTU = 1450
  PUBLIC_NETWORK_MTU         = 1500

  getter errors : Array(String)
  getter cilium : Configuration::Models::NetworkingConfig::CNIConfig::Cilium
  getter private_network : Configuration::Models::NetworkingConfig::PrivateNetwork

  def initialize(@errors, @cilium, @private_network)
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

    if cilium.helm_values_path && cilium.mtu
      errors << "Cilium mtu is ignored when helm_values_path is set; configure MTU in the Helm values file instead"
    end

    validate_mtu
  end

  private def validate_mtu
    mtu = cilium.mtu
    underlay_mtu = cilium.underlay_mtu

    if underlay_mtu && underlay_mtu < MIN_UNDERLAY_MTU
      errors << "Cilium underlay_mtu must be at least #{MIN_UNDERLAY_MTU} bytes"
    end

    if underlay_mtu && mtu.nil? && cilium.helm_values_path.nil?
      errors << "Cilium mtu must be set when underlay_mtu is configured"
    end

    return unless mtu

    effective_underlay_mtu = underlay_mtu || default_underlay_mtu
    overhead = encapsulation_overhead
    pod_mtu = mtu - overhead

    if mtu > effective_underlay_mtu
      errors << "Cilium mtu #{mtu} exceeds the configured underlay MTU #{effective_underlay_mtu}"
    end

    if pod_mtu < MIN_LARGE_PACKET_POD_MTU
      errors << "Cilium mtu #{mtu} leaves pod MTU #{pod_mtu} after #{overhead} bytes of encapsulation overhead; pod MTU must be at least #{MIN_LARGE_PACKET_POD_MTU}"
    end
  end

  private def encapsulation_overhead : Int32
    routing_mode = cilium.routing_mode || "tunnel"
    return 0 unless routing_mode == "tunnel"

    VXLAN_OVERHEAD_BYTES
  end

  private def default_underlay_mtu : Int32
    private_network.enabled ? HETZNER_PRIVATE_NETWORK_MTU : PUBLIC_NETWORK_MTU
  end
end
