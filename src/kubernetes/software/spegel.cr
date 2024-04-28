require "../../configuration/loader"
require "../../configuration/main"
require "../../util"
require "../../util/shell"

class Kubernetes::Software::Spegel
  include Util
  include Util::Shell

  getter configuration : Configuration::Loader
  getter settings : Configuration::Main { configuration.settings }

  def initialize(@configuration, @settings)
  end

  def install
    log_line "Installing Spegel..."

    command = <<-BASH
    helm upgrade --install \
    --version #{settings.additional_software.spegel.chart_version} \
    --create-namespace \
    --namespace spegel \
    --set spegel.containerdSock=/run/k3s/containerd/containerd.sock \
    --set spegel.containerdContentPath=/var/lib/rancher/k3s/agent/containerd/io.containerd.content.v1.content \
    --set spegel.containerdRegistryConfigPath=/var/lib/rancher/k3s/agent/etc/containerd/certs.d \
    --set spegel.logLevel="DEBUG" \
    spegel oci://ghcr.io/spegel-org/helm-charts/spegel
    BASH

    run_shell_command(command, configuration.kubeconfig_path, settings.hetzner_token)

    log_line "...Spegel installed"
  end

  private def default_log_prefix
    "Additional Software"
  end
end
