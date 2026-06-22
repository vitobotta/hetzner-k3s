require "crinja"

require "../../configuration/main"
require "../../configuration/loader"
require "../../configuration/models/external_node"
require "../deployment_helper"
require "../util"
require "./labels_and_taints_generator"

class Kubernetes::Script::WorkerGenerator
  include Util
  include Kubernetes::DeploymentHelper

  WORKER_INSTALL_SCRIPT = {{ read_file("#{__DIR__}/../../../templates/worker_install_script.sh") }}

  def initialize(@configuration : Configuration::Loader, @settings : Configuration::Main)
  end

  def generate_script(masters, first_master, worker_pool, external_node : Configuration::Models::ExternalNode? = nil)
    pool = worker_pool.not_nil!
    external_config = pool.external
    is_external = pool.external?
    labels_and_taints = ::Kubernetes::Script::LabelsAndTaintsGenerator.labels_and_taints(@settings, pool)
    post_k3s_commands = if is_external
                          "" # Post-k3s commands are run separately by ExternalSetup via SSH
                        else
                          format_post_k3s_commands(pool.additional_post_k3s_commands || @settings.additional_post_k3s_commands)
                        end

    Crinja.render(WORKER_INSTALL_SCRIPT, {
      cluster_name:                 @settings.cluster_name,
      k3s_token:                    generate_k3s_token(masters, first_master),
      k3s_version:                  @settings.k3s_version,
      api_server_ip_address:        api_server_ip_address(first_master),
      private_network_enabled:      @settings.networking.private_network.enabled.to_s,
      private_network_subnet:       @settings.networking.private_network.enabled ? @settings.networking.private_network.subnet : "",
      cluster_cidr:                 @settings.networking.cluster_cidr,
      service_cidr:                 @settings.networking.service_cidr,
      extra_args:                   kubelet_args_list(external_config),
      labels_and_taints:            labels_and_taints,
      private_registry_config:      @settings.addons.embedded_registry_mirror.private_registry_config,
      additional_post_k3s_commands: post_k3s_commands,
      is_external:                  is_external.to_s,
      kubelet_provider_id:          kubelet_provider_id(pool, external_node),
    })
  end

  private def kubelet_args_list(external_config : Configuration::Models::ExternalConfig?)
    args = @settings.all_kubelet_args
    args = args.reject { |arg| arg.starts_with?("cloud-provider=") } if external_config.try(&.generic?)

    ::Kubernetes::Util.kubernetes_component_args_list("kubelet", args)
  end

  private def kubelet_provider_id(pool, external_node : Configuration::Models::ExternalNode?) : String
    external_config = pool.external
    return "" unless pool.external? && external_config

    if external_config.robot?
      robot_server_number = external_node.try(&.robot_server_number)
      raise "Robot external node is missing robot_server_number" unless robot_server_number

      "hrobot://#{robot_server_number}"
    else
      "external://$PUBLIC_IP"
    end
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
