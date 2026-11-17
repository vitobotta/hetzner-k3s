require "../../configuration/loader"
require "../../configuration/main"
require "../../configuration/models/networking_config/cni_config/cilium_mtu"
require "../../util"
require "../../util/shell"
require "crinja"

class CiliumInstallationError < Exception; end

class CiliumConfigError < Exception; end

class Kubernetes::Software::Cilium
  include Util
  include Util::Shell

  alias CiliumMTU = Configuration::Models::NetworkingConfig::CNIConfig::CiliumMTU

  # Constants
  DEFAULT_NAMESPACE               = "kube-system"
  HELM_REPO_URL                   = "https://helm.cilium.io/"
  HELM_CHART_NAME                 = "cilium/cilium"
  DEFAULT_K8S_SERVICE_HOST        = "127.0.0.1"
  DEFAULT_K8S_SERVICE_PORT        = 6444
  DEFAULT_OPERATOR_REPLICAS       =    1
  DEFAULT_OPERATOR_MEMORY_REQUEST = "128Mi"
  DEFAULT_AGENT_MEMORY_REQUEST    = "512Mi"
  DEFAULT_ENCRYPTION_TYPE         = Configuration::Models::NetworkingConfig::CNIConfig::Cilium::DEFAULT_ENCRYPTION_TYPE
  DEFAULT_ROUTING_MODE            = Configuration::Models::NetworkingConfig::CNIConfig::Cilium::DEFAULT_ROUTING_MODE
  DEFAULT_TUNNEL_PROTOCOL         = "vxlan"

  CILIUM_VALUES_TEMPLATE = {{ read_file("#{__DIR__}/../../../templates/cilium_values.yaml") }}

  # Cross-node pod-to-pod check: a small ping, then a ping as large as the pod MTU
  # with the don't-fragment bit set, which fails when the MTU Cilium gives pods
  # does not fit the network path. The inputs (namespace, image, timeout_seconds,
  # expected_pod_mtu) are prepended as shell variables.
  CONNECTIVITY_CHECK_SCRIPT = <<-'BASH'
    set -euo pipefail

    run_id="cilium-netcheck-$(date +%s)-$RANDOM"
    src_pod="${run_id}-src"
    dst_pod="${run_id}-dst"

    cleanup() {
      kubectl -n "$namespace" delete pod "$src_pod" "$dst_pod" --ignore-not-found --wait=false >/dev/null 2>&1 || true
    }
    trap cleanup EXIT

    fail() {
      echo "Network validation failed: $*" >&2
      exit 1
    }

    ready_nodes() {
      kubectl get nodes --no-headers -l "$1" | awk '$2 ~ /^Ready/ {print $1}'
    }

    pod_manifest() {
      cat <<EOF
    ---
    apiVersion: v1
    kind: Pod
    metadata:
      name: $1
      namespace: $namespace
      labels:
        app.kubernetes.io/name: cilium-network-validation
    spec:
      restartPolicy: Never
      terminationGracePeriodSeconds: 0
      automountServiceAccountToken: false
      nodeName: $2
      tolerations:
      - operator: Exists
      containers:
      - name: netshoot
        image: "$image"
        imagePullPolicy: IfNotPresent
        command: ["sleep", "3600"]
    EOF
    }

    # Workers may have only just joined: let Cilium and the nodes settle before picking test nodes.
    kubectl -n "$namespace" rollout status ds cilium --timeout="${timeout_seconds}s" >/dev/null 2>&1 || true
    kubectl wait --for=condition=Ready nodes --all --timeout="${timeout_seconds}s" >/dev/null 2>&1 || true

    # Prefer two workers (the path regular workloads use), then fall back to control plane nodes.
    workers="$(ready_nodes '!node-role.kubernetes.io/control-plane')"
    masters="$(ready_nodes 'node-role.kubernetes.io/control-plane')"
    nodes=()
    for node in $workers $masters; do
      nodes+=("$node")
    done

    if [ "${#nodes[@]}" -lt 2 ]; then
      echo "Skipping Cilium cross-node network validation: it needs at least two Ready nodes, found ${#nodes[@]}."
      exit 0
    fi

    src_node="${nodes[0]}"
    dst_node="${nodes[1]}"

    { pod_manifest "$src_pod" "$src_node"; pod_manifest "$dst_pod" "$dst_node"; } | kubectl apply -f - >/dev/null

    if ! kubectl -n "$namespace" wait --for=condition=Ready "pod/$src_pod" "pod/$dst_pod" --timeout="${timeout_seconds}s" >/dev/null; then
      kubectl -n "$namespace" get pod "$src_pod" "$dst_pod" -o wide >&2 || true
      fail "test pods did not become Ready within ${timeout_seconds}s. If image $image cannot be pulled (for example in air-gapped clusters or with registry mirrors), set networking.cni.cilium.connectivity_check.image, or disable the check with networking.cni.cilium.connectivity_check.enabled: false."
    fi

    dst_ip="$(kubectl -n "$namespace" get pod "$dst_pod" -o jsonpath='{.status.podIP}')"
    [ -n "$dst_ip" ] || fail "destination pod $dst_pod did not receive a pod IP."

    case "$dst_ip" in
      *:*) ip_family="-6"; header_bytes=48 ;; # IPv6 (40) + ICMPv6 (8)
      *) ip_family="-4"; header_bytes=28 ;;   # IPv4 (20) + ICMP (8)
    esac

    # Cilium keeps the configured MTU on the pod's eth0 and sets the MTU reduced by the
    # tunnel/encryption overhead on the pod's routes, so the pod MTU is the lowest of them.
    mtu_report="$(kubectl -n "$namespace" exec "$src_pod" -- sh -c 'cat /sys/class/net/eth0/mtu; ip "$1" route get "$2"; ip "$1" route show default' sh "$ip_family" "$dst_ip")" \
      || fail "could not read the interface and route MTU of $src_pod."

    pod_mtu="$(printf '%s\n' "$mtu_report" | awk '
      NR == 1 { mtu = $1 + 0; next }
      {
        for (i = 1; i < NF; i++) {
          if ($i != "mtu") continue
          value = ($(i + 1) == "lock") ? $(i + 2) : $(i + 1)
          if (value ~ /^[0-9]+$/ && value + 0 < mtu) mtu = value + 0
        }
      }
      END { print mtu }
    ')"

    case "$pod_mtu" in
      '' | *[!0-9]* | 0) fail "could not determine the pod MTU of $src_pod from: $mtu_report" ;;
    esac

    if [ "$expected_pod_mtu" -gt 0 ] && [ "$pod_mtu" -gt "$expected_pod_mtu" ]; then
      fail "$src_pod on $src_node uses a pod MTU of $pod_mtu, but the configured Cilium MTU allows at most $expected_pod_mtu after tunnel/encryption overhead, so Cilium did not apply the configured MTU."
    fi

    if ! output="$(kubectl -n "$namespace" exec "$src_pod" -- ping -c 3 -W 2 "$dst_ip" 2>&1)"; then
      fail "small packet ping from $src_pod on $src_node to $dst_pod on $dst_node ($dst_ip) failed.
    $output"
    fi

    payload=$((pod_mtu - header_bytes))
    if ! output="$(kubectl -n "$namespace" exec "$src_pod" -- ping -c 3 -W 2 -M do -s "$payload" "$dst_ip" 2>&1)"; then
      fail "${pod_mtu}-byte ping (the pod MTU, don't fragment) from $src_pod on $src_node to $dst_pod on $dst_node ($dst_ip) failed. Packets of the pod MTU are dropped on the way: check Cilium's MTU against the network path MTU, including tunnel and encryption overhead.
    $output"
    fi

    echo "Cilium cross-node network validation passed: small ping and ${pod_mtu}-byte (pod MTU) ping from $src_node to $dst_node."
    BASH

  private getter configuration : Configuration::Loader
  private getter settings : Configuration::Main { configuration.settings }

  def initialize(@configuration, @settings)
  end

  def install
    log_line "Installing Cilium..."

    setup_helm_repo
    install_cilium
    wait_for_cilium_ready

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

  # Runs once all static nodes have joined, so the test can use two workers when
  # the cluster has them. Clusters with a single Ready node skip it with a warning.
  def validate_network_connectivity
    check = settings.networking.cni.cilium.connectivity_check

    unless check.enabled?
      log_line "Skipping Cilium cross-node network validation (networking.cni.cilium.connectivity_check.enabled is false)"
      return
    end

    log_line "Validating Cilium cross-node pod networking..."

    result = run_shell_command(
      connectivity_check_command(check),
      configuration.kubeconfig_path,
      settings.hetzner_token,
      abort_on_error: false
    )

    unless result.success?
      raise CiliumInstallationError.new("Failed Cilium network validation: #{result.output}")
    end
  end

  private def connectivity_check_command(check : Configuration::Models::NetworkingConfig::CNIConfig::CiliumConnectivityCheck) : String
    inputs = {
      "namespace"        => DEFAULT_NAMESPACE,
      "image"            => check.image,
      "timeout_seconds"  => check.timeout_seconds.to_s,
      "expected_pod_mtu" => (expected_pod_mtu || 0).to_s,
    }

    variables = inputs.join("\n") { |name, value| "#{name}=#{Process.quote(value)}" }

    "#{variables}\n#{CONNECTIVITY_CHECK_SCRIPT}"
  end

  # Largest pod MTU the configured Cilium MTU allows once tunnel and encryption
  # overhead are subtracted, or nil when Cilium auto-detects the MTU.
  private def expected_pod_mtu : Int32?
    helm_values_path = settings.networking.cni.cilium.helm_values_path

    mtu_settings = if helm_values_path && File.exists?(helm_values_path)
                     CiliumMTU.settings_from_helm_values(File.read(helm_values_path))
                   else
                     CiliumMTU.settings_from_config(settings.networking.cni)
                   end

    mtu_settings.pod_mtu
  rescue ex : CiliumMTU::Error
    raise CiliumConfigError.new("Failed to read the MTU from Cilium helm values file '#{helm_values_path}': #{ex.message}")
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
      mtu:                     CiliumMTU.explicit_mtu(cilium_config.mtu),
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
