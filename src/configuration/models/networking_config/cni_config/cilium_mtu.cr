require "yaml"
require "./cilium"
require "../cni"

# MTU rules shared by the configuration validator and the Cilium installer.
#
# The overhead values follow Cilium's own MTU calculation (pkg/mtu), so the pod
# MTU computed here matches the route MTU that Cilium programs inside pods:
# the pod's eth0 keeps the configured MTU, while its routes are reduced by the
# tunnel and encryption overhead. Cilium changed the WireGuard overhead in
# v1.19.5, so that one depends on the chart version in use.
module Configuration::Models::NetworkingConfig::CNIConfig::CiliumMTU
  TUNNEL_OVERHEAD_BYTES      =   50
  WIREGUARD_OVERHEAD_LEGACY  =   80 # up to and including Cilium v1.19.0
  WIREGUARD_OVERHEAD_CURRENT =   95 # Cilium v1.19.5 and later
  IPSEC_OVERHEAD_BYTES       =   77
  MIN_UNDERLAY_MTU           = 1280
  MIN_POD_MTU                = 1230
  # The kernel refuses to bring up IPv6 on an interface whose MTU is below this,
  # so a dual stack pod network needs the higher floor.
  MIN_POD_MTU_DUAL_STACK      = 1280
  HETZNER_PRIVATE_NETWORK_MTU = 1450
  PUBLIC_NETWORK_MTU          = 1500

  # First Cilium release with the 95 byte WireGuard overhead.
  WIREGUARD_OVERHEAD_CHANGE = {1, 19, 5}

  # Cilium Helm chart defaults, used when a custom values file leaves these unset.
  HELM_CHART_DEFAULT_ROUTING_MODE    = "tunnel"
  HELM_CHART_DEFAULT_ENCRYPTION_TYPE = "ipsec"

  class Error < Exception; end

  # The Cilium settings that determine the pod MTU. `encryption_type` is nil when
  # encryption is disabled.
  record Settings, mtu : Int32?, routing_mode : String, encryption_type : String?, chart_version : String? = nil do
    def explicit_mtu : Int32?
      CiliumMTU.explicit_mtu(mtu)
    end

    def overhead : Int32
      CiliumMTU.overhead(routing_mode, encryption_type, chart_version)
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

  def self.min_pod_mtu(dual_stack : Bool) : Int32
    dual_stack ? MIN_POD_MTU_DUAL_STACK : MIN_POD_MTU
  end

  # A pod network with an IPv6 CIDR needs an MTU of at least 1280 inside pods,
  # because the kernel does not bring up IPv6 below that.
  def self.dual_stack?(cluster_cidr : String?, service_cidr : String?) : Bool
    (cluster_cidr || "").includes?(":") || (service_cidr || "").includes?(":")
  end

  def self.overhead(routing_mode : String?, encryption_type : String?, chart_version : String? = nil) : Int32
    tunnel_mode = routing_mode.nil? || routing_mode.empty? || routing_mode == "tunnel"
    tunnel_overhead = tunnel_mode ? TUNNEL_OVERHEAD_BYTES : 0

    encryption_overhead = case encryption_type
                          when "wireguard" then wireguard_overhead(chart_version)
                          when "ipsec"     then IPSEC_OVERHEAD_BYTES
                          else                  0
                          end

    tunnel_overhead + encryption_overhead
  end

  # Cilium raised the WireGuard overhead from 80 to 95 bytes in v1.19.5. An
  # unparsable or missing version keeps the older value, which is what the pinned
  # default chart uses.
  def self.wireguard_overhead(chart_version : String?) : Int32
    version = chart_version.try { |value| version_number(value) }
    return WIREGUARD_OVERHEAD_LEGACY unless version

    major, minor, patch = version
    change_major, change_minor, change_patch = WIREGUARD_OVERHEAD_CHANGE
    current = major > change_major ||
              (major == change_major && (minor > change_minor ||
                                         (minor == change_minor && patch >= change_patch)))

    current ? WIREGUARD_OVERHEAD_CURRENT : WIREGUARD_OVERHEAD_LEGACY
  end

  private def self.version_number(value : String) : Tuple(Int32, Int32, Int32)?
    match = value.strip.match(/^v?(\d+)\.(\d+)\.(\d+)/)
    return unless match

    {match[1].to_i, match[2].to_i, match[3].to_i}
  end

  # Reasons why an explicit `mtu` does not fit the network path; empty when it does.
  # `underlay_source` describes where `underlay_mtu` came from, for the error message.
  def self.problems(mtu : Int32, underlay_mtu : Int32, overhead : Int32, underlay_source : String? = nil, min_pod_mtu : Int32 = MIN_POD_MTU) : Array(String)
    problems = [] of String
    pod_mtu = mtu - overhead

    if mtu > underlay_mtu
      problems << "MTU #{mtu} exceeds the network path MTU #{underlay_mtu}#{underlay_source.try { |source| " (#{source})" }}"
    end

    if pod_mtu < min_pod_mtu
      problems << "MTU #{mtu} leaves a pod MTU of #{pod_mtu} after #{overhead} bytes of tunnel/encryption overhead; pod MTU must be at least #{min_pod_mtu}"
    end

    problems
  end

  # Settings that hetzner-k3s renders into its own Cilium Helm values.
  def self.settings_from_config(cni : Configuration::Models::NetworkingConfig::CNI) : Settings
    cilium = cni.cilium

    Settings.new(
      mtu: cilium.mtu,
      routing_mode: cilium.routing_mode || Cilium::DEFAULT_ROUTING_MODE,
      encryption_type: cni.encryption ? (cilium.encryption_type || Cilium::DEFAULT_ENCRYPTION_TYPE) : nil,
      chart_version: cilium.chart_version
    )
  end

  # Settings from a custom Cilium Helm values file. Empty and comments-only files
  # are valid for `helm --values`, so they yield the chart defaults.
  def self.settings_from_helm_values(content : String, chart_version : String? = nil) : Settings
    values = YAML.parse(content)

    routing_mode = hash_value(values, "routingMode").try(&.as_s?).presence || HELM_CHART_DEFAULT_ROUTING_MODE

    encryption = hash_value(values, "encryption")
    encryption_enabled = hash_value(encryption, "enabled").try(&.as_bool?) || false
    encryption_type = hash_value(encryption, "type").try(&.as_s?).presence || HELM_CHART_DEFAULT_ENCRYPTION_TYPE

    Settings.new(
      mtu: helm_values_mtu(values),
      routing_mode: routing_mode,
      encryption_type: encryption_enabled ? encryption_type : nil,
      chart_version: chart_version
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
