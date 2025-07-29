require "../../configuration/loader"
require "../../configuration/main"
require "../../util"
require "../../util/shell"

class Kubernetes::Software::Cilium
  include Util
  include Util::Shell

  getter configuration : Configuration::Loader
  getter settings : Configuration::Main { configuration.settings }

  def initialize(@configuration, @settings)
  end

  def install
    log_line "Installing Cilium..."

    helm_values_path = settings.networking.cni.cilium.helm_values_path
    
    helm_repo_command = "helm repo add cilium https://helm.cilium.io/"
    helm_install_command = "helm upgrade --install --version #{settings.networking.cni.cilium.chart_version} --namespace kube-system"
    
    if helm_values_path && File.exists?(helm_values_path)
      helm_install_command += " --values #{helm_values_path}"
    else
      helm_install_command += " --set encryption.enabled=#{settings.networking.cni.encryption.to_s}"
      helm_install_command += " --set encryption.type=wireguard"
      helm_install_command += " --set encryption.nodeEncryption=#{settings.networking.cni.encryption.to_s}"
      helm_install_command += " --set routingMode=tunnel"
      helm_install_command += " --set tunnelProtocol=vxlan"
      helm_install_command += " --set ipam.mode=\"kubernetes\""
      helm_install_command += " --set kubeProxyReplacement=true"
      helm_install_command += " --set hubble.enabled=true"
      helm_install_command += " --set hubble.metrics.enabled=\"{dns,drop,tcp,flow,port-distribution,icmp,http}\""
      helm_install_command += " --set hubble.relay.enabled=true"
      helm_install_command += " --set hubble.ui.enabled=true"
      helm_install_command += " --set k8sServiceHost=127.0.0.1"
      helm_install_command += " --set k8sServicePort=6444"
      helm_install_command += " --set operator.replicas=1"
      helm_install_command += " --set operator.resources.requests.memory=128Mi"
      helm_install_command += " --set resources.requests.memory=512Mi"
      helm_install_command += " --set egressGateway.enabled=#{settings.networking.cni.cilium_egress_gateway.to_s}"
      helm_install_command += " --set bpf.masquerade=#{settings.networking.cni.cilium_egress_gateway.to_s}"
    end
    
    helm_install_command += " cilium cilium/cilium"

    command = <<-BASH
    #{helm_repo_command}
    #{helm_install_command}

    echo "Waiting for Cilium to be ready..."
    kubectl -n kube-system rollout status ds cilium
    BASH

    result = run_shell_command(command, configuration.kubeconfig_path, settings.hetzner_token)

    unless result.success?
      log_line "Failed to install Cilium CNI: #{result.output}"
      exit 1
    end

    log_line "...Cilium installed"
  end

  private def default_log_prefix
    "CNI"
  end
end
