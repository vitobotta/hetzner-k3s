require "../../configuration/loader"
require "../../configuration/main"
require "../../util"
require "../../util/shell"
require "crinja"

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

  CILIUM_VALUES_TEMPLATE = {{ read_file("#{__DIR__}/../../../templates/cilium_values.yaml") }}

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
