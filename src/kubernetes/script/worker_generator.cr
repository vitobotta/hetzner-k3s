require "crinja"

require "../../configuration/main"
require "../../configuration/loader"
require "../deployment_helper"
require "../util"
require "./labels_and_taints_generator"

class Kubernetes::Script::WorkerGenerator
  include Util
  include Kubernetes::DeploymentHelper

  WORKER_INSTALL_SCRIPT = {{ read_file("#{__DIR__}/../../../templates/worker_install_script.sh") }}

  def initialize(@configuration : Configuration::Loader, @settings : Configuration::Main)
  end

  def generate_script(masters, first_master, worker_pool)
    pool = worker_pool.not_nil!
    labels_and_taints = ::Kubernetes::Script::LabelsAndTaintsGenerator.labels_and_taints(@settings, pool)
    post_k3s_commands = format_post_k3s_commands(pool.additional_post_k3s_commands || @settings.additional_post_k3s_commands)

    Crinja.render(WORKER_INSTALL_SCRIPT, {
      cluster_name:            @settings.cluster_name,
      k3s_token:               generate_k3s_token(masters, first_master),
      k3s_version:             @settings.k3s_version,
      api_server_ip_address:   api_server_ip_address(first_master),
      private_network_enabled: @settings.networking.private_network.enabled.to_s,
      private_network_subnet:  @settings.networking.private_network.enabled ? @settings.networking.private_network.subnet : "",
      cluster_cidr:            @settings.networking.cluster_cidr,
      service_cidr:            @settings.networking.service_cidr,
      extra_args:              kubelet_args_list,
      labels_and_taints:       labels_and_taints,
      additional_post_k3s_commands: post_k3s_commands,
    })
  end

  private def kubelet_args_list
    ::Kubernetes::Util.kubernetes_component_args_list("kubelet", @settings.all_kubelet_args)
  end

  private def generate_k3s_token(masters, first_master)
    K3s.k3s_token(@settings, masters)
  end

  private def default_log_prefix
    "Kubernetes Script Worker"
  end

  private def format_post_k3s_commands(commands : Array(String)) : String
    return "" if commands.empty?

    commands.join("\n")
  end
end
