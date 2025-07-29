require "../../configuration/loader"
require "../../configuration/main"
require "../../util"
require "../../util/shell"

class CiliumInstallationError < Exception; end
class CiliumConfigError < Exception; end

class Kubernetes::Software::Cilium
  include Util
  include Util::Shell

  # Constants
  DEFAULT_NAMESPACE = "kube-system"
  HELM_REPO_URL = "https://helm.cilium.io/"
  HELM_CHART_NAME = "cilium/cilium"
  DEFAULT_K8S_SERVICE_HOST = "127.0.0.1"
  DEFAULT_K8S_SERVICE_PORT = 6444
  DEFAULT_OPERATOR_REPLICAS = 1
  DEFAULT_OPERATOR_MEMORY_REQUEST = "128Mi"
  DEFAULT_AGENT_MEMORY_REQUEST = "512Mi"
  DEFAULT_ENCRYPTION_TYPE = "wireguard"
  DEFAULT_ROUTING_MODE = "tunnel"
  DEFAULT_TUNNEL_PROTOCOL = "vxlan"
  DEFAULT_HUBBLE_METRICS = "{dns,drop,tcp,flow,port-distribution,icmp,http}"

  getter configuration : Configuration::Loader
  getter settings : Configuration::Main { configuration.settings }

  def initialize(@configuration, @settings)
  end

  # Install Cilium CNI on the cluster
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
    helm_command = build_helm_command
    result = run_shell_command(helm_command, configuration.kubeconfig_path, settings.hetzner_token)
    
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

  private def build_helm_command
    version = sanitize_version(settings.networking.cni.cilium.chart_version)
    
    cmd = ["helm upgrade --install --version #{version} --namespace #{DEFAULT_NAMESPACE}"]
    
    helm_values_path = settings.networking.cni.cilium.helm_values_path
    if helm_values_path && File.exists?(helm_values_path)
      cmd << "--values #{helm_values_path}"
    else
      cmd << build_helm_set_flags.join(" ")
    end
    
    cmd << "cilium #{HELM_CHART_NAME}"
    cmd.join(" ")
  end

  private def sanitize_version(version : String) : String
    version.strip
  end

  private def build_helm_set_flags
    flags = [] of String
    
    flags.concat(build_encryption_flags)
    flags.concat(build_routing_flags)
    flags.concat(build_ipam_flags)
    flags.concat(build_kube_proxy_flags)
    flags.concat(build_hubble_flags)
    flags.concat(build_k8s_service_flags)
    flags.concat(build_resource_flags)
    flags.concat(build_egress_flags)
    
    flags
  end

  private def build_encryption_flags
    encryption = settings.networking.cni.encryption
    cilium_config = settings.networking.cni.cilium
    
    [
      "--set encryption.enabled=#{encryption}",
      "--set encryption.type=#{cilium_config.encryption_type || DEFAULT_ENCRYPTION_TYPE}",
      "--set encryption.nodeEncryption=#{encryption}"
    ]
  end

  private def build_routing_flags
    cilium_config = settings.networking.cni.cilium
    
    [
      "--set routingMode=#{cilium_config.routing_mode || DEFAULT_ROUTING_MODE}",
      "--set tunnelProtocol=#{cilium_config.tunnel_protocol || DEFAULT_TUNNEL_PROTOCOL}"
    ]
  end

  private def build_ipam_flags
    ["--set ipam.mode=\"kubernetes\""]
  end

  private def build_kube_proxy_flags
    ["--set kubeProxyReplacement=true"]
  end

  private def build_hubble_flags
    cilium_config = settings.networking.cni.cilium
    
    [
      "--set hubble.enabled=#{cilium_config.hubble_enabled || true}",
      "--set hubble.metrics.enabled=\"#{cilium_config.hubble_metrics || DEFAULT_HUBBLE_METRICS}\"",
      "--set hubble.relay.enabled=#{cilium_config.hubble_relay_enabled || true}",
      "--set hubble.ui.enabled=#{cilium_config.hubble_ui_enabled || true}"
    ]
  end

  private def build_k8s_service_flags
    cilium_config = settings.networking.cni.cilium
    
    [
      "--set k8sServiceHost=#{cilium_config.k8s_service_host || DEFAULT_K8S_SERVICE_HOST}",
      "--set k8sServicePort=#{cilium_config.k8s_service_port || DEFAULT_K8S_SERVICE_PORT}"
    ]
  end

  private def build_resource_flags
    cilium_config = settings.networking.cni.cilium
    
    [
      "--set operator.replicas=#{cilium_config.operator_replicas || DEFAULT_OPERATOR_REPLICAS}",
      "--set operator.resources.requests.memory=#{cilium_config.operator_memory_request || DEFAULT_OPERATOR_MEMORY_REQUEST}",
      "--set resources.requests.memory=#{cilium_config.agent_memory_request || DEFAULT_AGENT_MEMORY_REQUEST}"
    ]
  end

  private def build_egress_flags
    egress_gateway = settings.networking.cni.cilium_egress_gateway
    
    [
      "--set egressGateway.enabled=#{egress_gateway}",
      "--set bpf.masquerade=#{egress_gateway}"
    ]
  end

  private def default_log_prefix
    "CNI"
  end
end
