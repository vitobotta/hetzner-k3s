require "crinja"

require "../../configuration/main"
require "../../configuration/loader"
require "../deployment_helper"
require "../util"
require "./labels_and_taints_generator"

class Kubernetes::Script::MasterGenerator
  include Util
  include Kubernetes::DeploymentHelper

  MASTER_INSTALL_SCRIPT = {{ read_file("#{__DIR__}/../../../templates/master_install_script.sh") }}

  def initialize(@configuration : Configuration::Loader, @settings : Configuration::Main)
  end

  def generate_script(master, masters, first_master, load_balancer, kubeconfig_manager)
    server = ""
    datastore_endpoint = ""
    etcd_arguments = ""

    if @settings.datastore.mode == "etcd"
      server = master == first_master ? " --cluster-init " : " --server https://#{api_server_ip_address(first_master)}:6443 "
      etcd_arguments = " --etcd-expose-metrics=true #{@settings.datastore.etcd.generate_etcd_args} "
    else
      datastore_endpoint = " K3S_DATASTORE_ENDPOINT='#{@settings.datastore.external_datastore_endpoint}' "
    end

    extra_args = "#{kube_api_server_args_list} #{kube_scheduler_args_list} #{kube_controller_manager_args_list} #{kube_cloud_controller_manager_args_list} #{kubelet_args_list} #{kube_proxy_args_list}"
    master_taint = @settings.schedule_workloads_on_masters ? " " : " --node-taint CriticalAddonsOnly=true:NoExecute "
    labels_and_taints = ::Kubernetes::Script::LabelsAndTaintsGenerator.labels_and_taints(@settings, @settings.masters_pool)
    post_k3s_commands = format_post_k3s_commands(@settings.masters_pool.additional_post_k3s_commands || @settings.additional_post_k3s_commands)

    Crinja.render(MASTER_INSTALL_SCRIPT, {
      cluster_name:                     @settings.cluster_name,
      k3s_version:                      @settings.k3s_version,
      k3s_token:                        generate_k3s_token(masters, first_master),
      cni:                              @settings.networking.cni.enabled.to_s,
      cni_mode:                         @settings.networking.cni.mode,
      flannel_backend:                  flannel_backend,
      master_taint:                     master_taint,
      extra_args:                       extra_args,
      server:                           server,
      tls_sans:                         kubeconfig_manager.generate_tls_sans(masters, first_master, load_balancer),
      private_network_enabled:          @settings.networking.private_network.enabled.to_s,
      private_network_subnet:           @settings.networking.private_network.enabled ? @settings.networking.private_network.subnet : "",
      cluster_cidr:                     @settings.networking.cluster_cidr,
      service_cidr:                     @settings.networking.service_cidr,
      cluster_dns:                      @settings.networking.cluster_dns,
      datastore_endpoint:               datastore_endpoint,
      etcd_arguments:                   etcd_arguments,
      embedded_registry_mirror_enabled: @settings.addons.embedded_registry_mirror.enabled.to_s,
      local_path_storage_class_enabled: @settings.addons.local_path_storage_class.enabled.to_s,
      traefik_enabled: @settings.addons.traefik.enabled.to_s,
      servicelb_enabled: @settings.addons.servicelb.enabled.to_s,
      metrics_server_enabled: @settings.addons.metrics_server.enabled.to_s,
      labels_and_taints: labels_and_taints,
      additional_post_k3s_commands: post_k3s_commands
    })
  end

  private def kubelet_args_list
    ::Kubernetes::Util.kubernetes_component_args_list("kubelet", @settings.all_kubelet_args)
  end

  private def kube_api_server_args_list
    ::Kubernetes::Util.kubernetes_component_args_list("kube-apiserver", @settings.kube_api_server_args)
  end

  private def kube_scheduler_args_list
    ::Kubernetes::Util.kubernetes_component_args_list("kube-scheduler", @settings.kube_scheduler_args)
  end

  private def kube_controller_manager_args_list
    ::Kubernetes::Util.kubernetes_component_args_list("kube-controller-manager", @settings.kube_controller_manager_args)
  end

  private def kube_cloud_controller_manager_args_list
    ::Kubernetes::Util.kubernetes_component_args_list("kube-cloud-controller-manager", @settings.kube_cloud_controller_manager_args)
  end

  private def kube_proxy_args_list
    ::Kubernetes::Util.kubernetes_component_args_list("kube-proxy", @settings.kube_proxy_args)
  end

  private def flannel_backend
    if @settings.networking.cni.flannel? && @settings.networking.cni.encryption?
      available_releases = K3s.available_releases
      selected_k3s_index = available_releases.index(@settings.k3s_version).not_nil!
      k3s_1_23_6_index = available_releases.index("v1.23.6+k3s1").not_nil!

      selected_k3s_index >= k3s_1_23_6_index ? " --flannel-backend=wireguard-native " : " --flannel-backend=wireguard "
    elsif @settings.networking.cni.flannel?
      " "
    else
      args = ["--flannel-backend=none", "--disable-network-policy"]
      args << "--disable-kube-proxy" unless @settings.networking.cni.kube_proxy?
      args.join(" ")
    end
  end

  private def generate_k3s_token(masters, first_master)
    K3s.k3s_token(@settings, masters)
  end

  private def default_log_prefix
    "Kubernetes Script Master"
  end

  private def format_post_k3s_commands(commands : Array(String)) : String
    return "" if commands.empty?

    commands.join("\n")
  end
end
