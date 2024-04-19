require "../../util"
require "../util"

class Kubernetes::Software::Cilium
  include Util
  include Kubernetes::Util

  getter configuration : Configuration::Loader
  getter settings : Configuration::Main { configuration.settings }

  def initialize(@configuration, @settings)
  end

  def install
    log_line "Installing Cilium via Helm..."

    encryption = settings.networking.cni.encryption ? "true" : "false"

    command = <<-BASH
    helm repo add cilium https://helm.cilium.io/

    helm upgrade --install \
    --version 1.15.4 \
    --namespace kube-system \
    --set encryption.enabled=#{encryption} \
    --set encryption.type=wireguard \
    --set encryption.nodeEncryption=#{encryption} \
    --set ipam.operator.clusterPoolIPv4PodCIDRList="#{settings.networking.cluster_cidr}" \
    --set rollOutCiliumPods=true \
    --set operator.rollOutPods=true \
    --set kubeProxyReplacement=true \
    --set k8sServiceHost=127.0.0.1 \
    --set k8sServicePort=6444 \
    cilium cilium/cilium

    echo "Restarting Cilium pods for master nodes..."
    for node in $(kubectl get nodes -l node-role.kubernetes.io/master -o jsonpath='{.items[*].metadata.name}'); do
      kubectl -n kube-system delete pods -l k8s-app=cilium --field-selector=spec.nodeName=$node
    done

    echo "Restarting pending pods..."
    namespaces=$(kubectl get namespaces -o jsonpath='{.items[*].metadata.name}')

    for ns in $namespaces; do
      pod_names=$(kubectl get pods -n "$ns" --field-selector='status.phase!=Running,status.phase!=Succeeded,status.phase!=Failed' --output=jsonpath='{.items[*].metadata.name}')

      crashloopbackoff_pods=$(kubectl get pods -n "$ns" --field-selector='status.phase=Running' --output=jsonpath='{.items[?(.status.containerStatuses[].restartCount>0)].metadata.name}')

      for pod in $pod_names $crashloopbackoff_pods; do
        kubectl delete pod "$pod" -n "$ns"
      done
    done
    BASH

    result = run_shell_command(command, configuration.kubeconfig_path, settings.hetzner_token)

    unless result.success?
      log_line "Failed to install Cilium: #{result.output}"
      exit 1
    end

    log_line "...Cilium installed"
  end

  private def default_log_prefix
    "CNI"
  end
end
