require "yaml"
require "./cilium"
require "../cni"

# MTU rules shared by the configuration validator and the Cilium installer.
#
# The overhead values mirror Cilium's own MTU calculation (pkg/mtu), so the pod
# MTU computed here matches the route MTU that Cilium programs inside pods:
# the pod's eth0 keeps the configured MTU, while its routes are reduced by the
# tunnel and encryption overhead.
module Configuration::Models::NetworkingConfig::CNIConfig::CiliumMTU
  TUNNEL_OVERHEAD_BYTES       =   50
  WIREGUARD_OVERHEAD_BYTES    =   80
  IPSEC_OVERHEAD_BYTES        =   77
  MIN_UNDERLAY_MTU            = 1280
  MIN_POD_MTU                 = 1230
  HETZNER_PRIVATE_NETWORK_MTU = 1450
  PUBLIC_NETWORK_MTU          = 1500

  # Cilium Helm chart defaults, used when a custom values file leaves these unset.
  HELM_CHART_DEFAULT_ROUTING_MODE    = "tunnel"
  HELM_CHART_DEFAULT_ENCRYPTION_TYPE = "ipsec"

  class Error < Exception; end

  # The Cilium settings that determine the pod MTU. `encryption_type` is nil when
  # encryption is disabled.
  record Settings, mtu : Int32?, routing_mode : String, encryption_type : String? do
    def explicit_mtu : Int32?
      CiliumMTU.explicit_mtu(mtu)
    end

    def overhead : Int32
      CiliumMTU.overhead(routing_mode, encryption_type)
    end

    # Pod (route) MTU Cilium will use, or nil when Cilium auto-detects the MTU.
    def pod_mtu : Int32?
      explicit_mtu.try { |value| value - overhead }
    end
  end

  # Cilium treats a missing MTU or an MTU of 0 as "auto-detect from the
  # underlying device", so only positive values are explicit.
  def self.explicit_mtu(mtu : Int32?) : Int32?
    mtu if mtu && mtu > 0
  end

  def self.default_underlay_mtu(private_network_enabled : Bool) : Int32
    private_network_enabled ? HETZNER_PRIVATE_NETWORK_MTU : PUBLIC_NETWORK_MTU
  end

  def self.overhead(routing_mode : String?, encryption_type : String?) : Int32
    tunnel_mode = routing_mode.nil? || routing_mode.empty? || routing_mode == "tunnel"
    tunnel_overhead = tunnel_mode ? TUNNEL_OVERHEAD_BYTES : 0

    encryption_overhead = case encryption_type
                          when "wireguard" then WIREGUARD_OVERHEAD_BYTES
                          when "ipsec"     then IPSEC_OVERHEAD_BYTES
                          else                  0
                          end

    tunnel_overhead + encryption_overhead
  end

  # Reasons why an explicit `mtu` does not fit the network path; empty when it does.
  # `underlay_source` describes where `underlay_mtu` came from, for the error message.
  def self.problems(mtu : Int32, underlay_mtu : Int32, overhead : Int32, underlay_source : String? = nil) : Array(String)
    problems = [] of String
    pod_mtu = mtu - overhead

    if mtu > underlay_mtu
      problems << "MTU #{mtu} exceeds the network path MTU #{underlay_mtu}#{underlay_source.try { |source| " (#{source})" }}"
    end

    if pod_mtu < MIN_POD_MTU
      problems << "MTU #{mtu} leaves a pod MTU of #{pod_mtu} after #{overhead} bytes of tunnel/encryption overhead; pod MTU must be at least #{MIN_POD_MTU}"
    end

    problems
  end

  # Settings that hetzner-k3s renders into its own Cilium Helm values.
  def self.settings_from_config(cni : Configuration::Models::NetworkingConfig::CNI) : Settings
    cilium = cni.cilium

    Settings.new(
      mtu: cilium.mtu,
      routing_mode: cilium.routing_mode || Cilium::DEFAULT_ROUTING_MODE,
      encryption_type: cni.encryption ? (cilium.encryption_type || Cilium::DEFAULT_ENCRYPTION_TYPE) : nil
    )
  end

  # Settings from a custom Cilium Helm values file. Empty and comments-only files
  # are valid for `helm --values`, so they yield the chart defaults.
  def self.settings_from_helm_values(content : String) : Settings
    values = YAML.parse(content)

    routing_mode = hash_value(values, "routingMode").try(&.as_s?).presence || HELM_CHART_DEFAULT_ROUTING_MODE

    encryption = hash_value(values, "encryption")
    encryption_enabled = hash_value(encryption, "enabled").try(&.as_bool?) || false
    encryption_type = hash_value(encryption, "type").try(&.as_s?).presence || HELM_CHART_DEFAULT_ENCRYPTION_TYPE

    Settings.new(
      mtu: helm_values_mtu(values),
      routing_mode: routing_mode,
      encryption_type: encryption_enabled ? encryption_type : nil
    )
  rescue ex : YAML::ParseException
    raise Error.new("invalid YAML: #{ex.message}")
  end

  private def self.helm_values_mtu(values : YAML::Any) : Int32?
    node = hash_value(values, "MTU") || hash_value(values, "mtu")
    return unless node
    return if node.raw.nil?

    mtu = node.as_i? || node.as_s?.try(&.strip.to_i?)
    raise Error.new("MTU must be an integer, got '#{node}'") unless mtu

    mtu
  end

  private def self.hash_value(node : YAML::Any?, key : String) : YAML::Any?
    node.try(&.as_h?).try(&.[YAML::Any.new(key)]?)
  end
end
