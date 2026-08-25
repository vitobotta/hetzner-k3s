require "../../configuration/loader"
require "../../configuration/main"
require "../../util"
require "../../util/shell"
require "crinja"
require "yaml"

class CiliumInstallationError < Exception; end

class CiliumConfigError < Exception; end

class Kubernetes::Software::Cilium
  include Util
  include Util::Shell

  # Constants
  DEFAULT_NAMESPACE               = "kube-system"
  HELM_REPO_URL                   = "https://helm.cilium.io/"
  HELM_CHART_NAME                 = "cilium/cilium"
  DEFAULT_K8S_SERVICE_HOST        = "127.0.0.1"
  DEFAULT_K8S_SERVICE_PORT        = 6444
  DEFAULT_OPERATOR_REPLICAS       =    1
  DEFAULT_OPERATOR_MEMORY_REQUEST = "128Mi"
  DEFAULT_AGENT_MEMORY_REQUEST    = "512Mi"
  DEFAULT_ENCRYPTION_TYPE         = "wireguard"
  DEFAULT_ROUTING_MODE            = "tunnel"
  DEFAULT_TUNNEL_PROTOCOL         = "vxlan"
  VXLAN_OVERHEAD_BYTES            =   50
  MIN_LARGE_PACKET_POD_MTU        = 1230
  LARGE_PING_PAYLOAD_BYTES        = 1202
  MIN_UNDERLAY_MTU                = 1280
  HETZNER_PRIVATE_NETWORK_MTU     = 1450
  PUBLIC_NETWORK_MTU              = 1500
  NETWORK_TEST_IMAGE              = "nicolaka/netshoot:latest"

  CILIUM_VALUES_TEMPLATE = {{ read_file("#{__DIR__}/../../../templates/cilium_values.yaml") }}

  private getter configuration : Configuration::Loader
  private getter settings : Configuration::Main { configuration.settings }

  def initialize(@configuration, @settings)
  end

  def install
    log_line "Installing Cilium..."

    setup_helm_repo
    validate_mtu_configuration
    install_cilium
    wait_for_cilium_ready
    validate_network_connectivity

    log_line "...Cilium installed"
  end

  private def setup_helm_repo
    command = "helm repo add cilium #{HELM_REPO_URL}"
    result = run_shell_command(command, configuration.kubeconfig_path, settings.hetzner_token)

    unless result.success?
      raise CiliumInstallationError.new("Failed to add Cilium Helm repository: #{result.output}")
    end
  end

  private def install_cilium
    helm_values_path = settings.networking.cni.cilium.helm_values_path

    if helm_values_path && File.exists?(helm_values_path)
      result = run_shell_command(build_helm_command(helm_values_path), configuration.kubeconfig_path, settings.hetzner_token)
    else
      values_content = generate_helm_values
      values_file = File.tempname("cilium_helm_values", ".yml")

      begin
        File.write(values_file, values_content)
        File.chmod(values_file, 0o755)

        helm_command = build_helm_command(values_file)

        result = run_shell_command(helm_command, configuration.kubeconfig_path, settings.hetzner_token)
      ensure
        File.delete(values_file) if File.exists?(values_file)
      end
    end

    unless result.success?
      raise CiliumInstallationError.new("Failed to install Cilium CNI: #{result.output}")
    end
  end

  private def wait_for_cilium_ready
    command = "kubectl -n #{DEFAULT_NAMESPACE} rollout status ds cilium"
    result = run_shell_command(command, configuration.kubeconfig_path, settings.hetzner_token)

    unless result.success?
      raise CiliumInstallationError.new("Failed to verify Cilium rollout status: #{result.output}")
    end
  end

  private def validate_mtu_configuration
    configured_mtu = effective_cilium_mtu
    configured_underlay_mtu = settings.networking.cni.cilium.underlay_mtu
    underlay_mtu = configured_underlay_mtu || default_underlay_mtu

    if underlay_mtu < MIN_UNDERLAY_MTU
      raise CiliumConfigError.new("Cilium MTU validation failed: underlay MTU #{underlay_mtu} is below Kubernetes' minimum MTU #{MIN_UNDERLAY_MTU}")
    end

    unless configured_mtu
      if configured_underlay_mtu
        raise CiliumConfigError.new("Cilium MTU validation failed: underlay_mtu is set but no Cilium MTU was configured in networking.cni.cilium.mtu or the Helm values file")
      end

      log_line "Skipping Cilium MTU preflight: no explicit Cilium MTU configured", log_prefix: default_log_prefix
      return
    end

    overhead = cilium_encapsulation_overhead
    pod_mtu = configured_mtu - overhead
    errors = [] of String

    if configured_mtu > underlay_mtu
      errors << "configured MTU #{configured_mtu} exceeds the network path MTU #{underlay_mtu}"
    end

    if pod_mtu < MIN_LARGE_PACKET_POD_MTU
      errors << "configured MTU #{configured_mtu} leaves pod MTU #{pod_mtu} after #{overhead} bytes of encapsulation overhead; pod MTU must be at least #{MIN_LARGE_PACKET_POD_MTU}"
    end

    nodes_result = run_shell_command(
      "kubectl get nodes --no-headers",
      configuration.kubeconfig_path,
      settings.hetzner_token,
      abort_on_error: false,
      print_output: false
    )

    unless nodes_result.success?
      errors << "could not inspect Kubernetes nodes before installing Cilium: #{nodes_result.output}"
    end

    unless errors.empty?
      raise CiliumConfigError.new("Cilium MTU validation failed:\n - #{errors.join("\n - ")}")
    end

    source = configured_underlay_mtu ? "configured underlay_mtu" : "default underlay MTU"
    log_line "Cilium MTU preflight passed: configured MTU #{configured_mtu}, pod MTU #{pod_mtu}, #{source} #{underlay_mtu}", log_prefix: default_log_prefix
  end

  private def validate_network_connectivity
    command = <<-BASH
set -euo pipefail

namespace="#{DEFAULT_NAMESPACE}"
image="#{NETWORK_TEST_IMAGE}"
large_payload="#{LARGE_PING_PAYLOAD_BYTES}"
large_packet="#{MIN_LARGE_PACKET_POD_MTU}"
run_id="cilium-netcheck-$(date +%s)-$RANDOM"
src_pod="${run_id}-src"
dst_pod="${run_id}-dst"
small_ping_output="/tmp/${run_id}-small-ping.out"
large_ping_output="/tmp/${run_id}-large-ping.out"

cleanup() {
  kubectl -n "$namespace" delete pod "$src_pod" "$dst_pod" --ignore-not-found --wait=false >/dev/null 2>&1 || true
  rm -f "$small_ping_output" "$large_ping_output"
}
trap cleanup EXIT

nodes="$(kubectl get nodes --no-headers | awk '$2 ~ /^Ready/ {print $1}' | head -n 2)"
node_count="$(printf '%s\n' "$nodes" | sed '/^$/d' | wc -l | tr -d ' ')"

if [ "$node_count" -lt 2 ]; then
  echo "Network validation requires at least two Ready nodes for a cross-node Cilium MTU test; found $node_count." >&2
  exit 1
fi

src_node="$(printf '%s\n' "$nodes" | sed -n '1p')"
dst_node="$(printf '%s\n' "$nodes" | sed -n '2p')"

cat <<EOF | kubectl apply -f - >/dev/null
apiVersion: v1
kind: Pod
metadata:
  name: $src_pod
  namespace: $namespace
  labels:
    app.kubernetes.io/name: cilium-network-validation
spec:
  restartPolicy: Never
  terminationGracePeriodSeconds: 0
  nodeName: $src_node
  tolerations:
  - operator: Exists
  containers:
  - name: netshoot
    image: $image
    imagePullPolicy: IfNotPresent
    command: ["sh", "-c", "sleep 3600"]
---
apiVersion: v1
kind: Pod
metadata:
  name: $dst_pod
  namespace: $namespace
  labels:
    app.kubernetes.io/name: cilium-network-validation
spec:
  restartPolicy: Never
  terminationGracePeriodSeconds: 0
  nodeName: $dst_node
  tolerations:
  - operator: Exists
  containers:
  - name: netshoot
    image: $image
    imagePullPolicy: IfNotPresent
    command: ["sh", "-c", "sleep 3600"]
EOF

kubectl -n "$namespace" wait --for=condition=Ready "pod/$src_pod" "pod/$dst_pod" --timeout=180s >/dev/null
dst_ip="$(kubectl -n "$namespace" get pod "$dst_pod" -o jsonpath='{.status.podIP}')"

if [ -z "$dst_ip" ]; then
  echo "Network validation failed: destination pod did not receive a pod IP." >&2
  exit 1
fi

if ! kubectl -n "$namespace" exec "$src_pod" -- ping -c 3 -W 2 "$dst_ip" >"$small_ping_output" 2>&1; then
  echo "Network validation failed: small packet ping from $src_pod on $src_node to $dst_pod on $dst_node ($dst_ip) failed." >&2
  cat "$small_ping_output" >&2
  exit 1
fi

if ! kubectl -n "$namespace" exec "$src_pod" -- ping -c 3 -W 2 -M do -s "$large_payload" "$dst_ip" >"$large_ping_output" 2>&1; then
  echo "Network validation failed: ${large_packet}B large packet ping from $src_pod on $src_node to $dst_pod on $dst_node ($dst_ip) failed. Check Cilium MTU, VXLAN overhead, and the network path MTU." >&2
  cat "$large_ping_output" >&2
  exit 1
fi

echo "Cilium cross-node network validation passed: small ping and ${large_packet}B large packet ping from $src_node to $dst_node."
BASH

    result = run_shell_command(
      command,
      configuration.kubeconfig_path,
      settings.hetzner_token,
      abort_on_error: false
    )

    unless result.success?
      raise CiliumInstallationError.new("Failed Cilium network validation: #{result.output}")
    end
  end

  private def build_helm_command(helm_values_path : String)
    version = sanitize_version(settings.networking.cni.cilium.chart_version)

    cmd = ["helm upgrade --install --version #{version} --namespace #{DEFAULT_NAMESPACE}"]
    cmd << "--values #{helm_values_path}"
    cmd << "cilium #{HELM_CHART_NAME}"
    cmd.join(" ")
  end

  private def sanitize_version(version : String) : String
    version.strip
  end

  private def generate_helm_values
    cilium_config = settings.networking.cni.cilium

    template_vars = {
      mtu:                     cilium_config.mtu,
      encryption_enabled:      settings.networking.cni.encryption,
      encryption_type:         cilium_config.encryption_type || DEFAULT_ENCRYPTION_TYPE,
      routing_mode:            cilium_config.routing_mode || DEFAULT_ROUTING_MODE,
      tunnel_protocol:         cilium_config.tunnel_protocol || DEFAULT_TUNNEL_PROTOCOL,
      hubble_enabled:          cilium_config.hubble_enabled || true,
      hubble_metrics:          build_hubble_metrics_array(cilium_config.hubble_metrics),
      hubble_relay_enabled:    cilium_config.hubble_relay_enabled || true,
      hubble_ui_enabled:       cilium_config.hubble_ui_enabled || true,
      k8s_service_host:        cilium_config.k8s_service_host || DEFAULT_K8S_SERVICE_HOST,
      k8s_service_port:        cilium_config.k8s_service_port || DEFAULT_K8S_SERVICE_PORT,
      operator_replicas:       cilium_config.operator_replicas || DEFAULT_OPERATOR_REPLICAS,
      operator_memory_request: cilium_config.operator_memory_request || DEFAULT_OPERATOR_MEMORY_REQUEST,
      agent_memory_request:    cilium_config.agent_memory_request || DEFAULT_AGENT_MEMORY_REQUEST,
      egress_gateway_enabled:  settings.networking.cni.cilium_egress_gateway,
    }

    Crinja.render(CILIUM_VALUES_TEMPLATE, template_vars)
  end

  private def effective_cilium_mtu : Int32?
    helm_values_path = settings.networking.cni.cilium.helm_values_path
    return mtu_from_helm_values(helm_values_path) if helm_values_path && File.exists?(helm_values_path)

    settings.networking.cni.cilium.mtu
  end

  private def mtu_from_helm_values(helm_values_path : String) : Int32?
    values = YAML.parse(File.read(helm_values_path))
    mtu_node = values["MTU"]? || values["mtu"]?
    return unless mtu_node

    mtu = yaml_value_to_i(mtu_node)
    raise "MTU must be an integer" unless mtu

    mtu
  rescue ex
    raise CiliumConfigError.new("Failed to parse Cilium helm values file '#{helm_values_path}' for MTU validation: #{ex.message}")
  end

  private def yaml_value_to_i(value : YAML::Any) : Int32?
    begin
      value.as_i
    rescue
      begin
        value.as_s.to_i?
      rescue
        nil
      end
    end
  end

  private def default_underlay_mtu : Int32
    settings.networking.private_network.enabled ? HETZNER_PRIVATE_NETWORK_MTU : PUBLIC_NETWORK_MTU
  end

  private def cilium_encapsulation_overhead : Int32
    routing_mode = settings.networking.cni.cilium.routing_mode || DEFAULT_ROUTING_MODE
    return 0 unless routing_mode == "tunnel"

    VXLAN_OVERHEAD_BYTES
  end

  private def build_hubble_metrics_array(custom_metrics : String?) : Array(String)
    if custom_metrics
      custom_metrics.split(/[{} ,]+/).reject &.empty?
    else
      ["dns", "drop", "tcp", "flow", "port-distribution", "icmp", "http"]
    end
  end

  private def default_log_prefix
    "CNI"
  end
end
