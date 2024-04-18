require "crinja"
require "base64"
require "file_utils"

require "../util"
require "../util/ssh"
require "../util/shell"
require "../kubernetes/util"
require "../hetzner/instance"
require "../hetzner/load_balancer"
require "../configuration/loader"
require "./software/system_upgrade_controller"
require "./software/hetzner/secret"
require "./software/hetzner/cloud_controller_manager"
require "./software/hetzner/csi_driver"
require "./software/cluster_autoscaler"

class Kubernetes::Installer
  include Util
  include Util::Shell

  MASTER_INSTALL_SCRIPT = {{ read_file("#{__DIR__}/../../templates/master_install_script.sh") }}
  WORKER_INSTALL_SCRIPT = {{ read_file("#{__DIR__}/../../templates/worker_install_script.sh") }}

  getter configuration : Configuration::Loader
  getter settings : Configuration::Main { configuration.settings }
  getter masters : Array(Hetzner::Instance) = [] of Hetzner::Instance
  getter workers : Array(Hetzner::Instance) = [] of Hetzner::Instance
  getter autoscaling_worker_node_pools : Array(Configuration::NodePool)
  getter load_balancer : Hetzner::LoadBalancer?
  getter ssh : ::Util::SSH

  def initialize(
      @configuration,
      @load_balancer,
      @ssh,
      @autoscaling_worker_node_pools
    )
  end

  def run(masters_installation_queue_channel, workers_installation_queue_channel, master_count, worker_count)
    ensure_kubectl_is_installed!

    set_up_control_plane(masters_installation_queue_channel, master_count)
    set_up_workers(workers_installation_queue_channel, worker_count)

    add_labels_and_taints_to_masters
    add_labels_and_taints_to_workers

    install_software
  end

  private def set_up_control_plane(masters_installation_queue_channel, master_count)
    masters_ready_channel = Channel(Hetzner::Instance).new

    master = masters_installation_queue_channel.receive
    masters << master

    set_up_first_master(master_count)

    mutex = Mutex.new

    (master_count - 1).times do
      spawn do
        master = masters_installation_queue_channel.receive
        mutex.synchronize { masters << master }
        deploy_k3s_to_master(master, master_count)
        masters_ready_channel.send(master)
      end
    end

    (master_count - 1).times do
      masters_ready_channel.receive
    end
  end

  private def set_up_workers(workers_installation_queue_channel, worker_count)
    workers_ready_channel = Channel(Hetzner::Instance).new

    mutex = Mutex.new

    worker_count.times do
      spawn do
        worker = workers_installation_queue_channel.receive
        mutex.synchronize { workers << worker }
        deploy_k3s_to_worker(worker)
        workers_ready_channel.send(worker)
      end
    end

    worker_count.times do
      workers_ready_channel.receive
    end
  end

  private def set_up_first_master(master_count)
    log_line "Deploying k3s...", log_prefix: "Instance #{first_master.name}"

    output = ssh.run(first_master, settings.ssh_port, master_install_script(first_master, master_count), settings.use_ssh_agent)

    log_line  "Waiting for the control plane to be ready...", log_prefix: "Instance #{first_master.name}"

    sleep 10 unless /No change detected/ =~ output

    log_line "...k3s deployed", log_prefix: "Instance #{first_master.name}"

    save_kubeconfig(master_count)
  end

  private def deploy_k3s_to_master(master : Hetzner::Instance, master_count)
    log_line "Deploying k3s...", log_prefix: "Instance #{master.name}"
    ssh.run(master, settings.ssh_port, master_install_script(master, master_count), settings.use_ssh_agent)
    log_line "...k3s deployed", log_prefix: "Instance #{master.name}"
  end

  private def deploy_k3s_to_worker(worker : Hetzner::Instance)
    log_line "Deploying k3s to worker #{worker.name}...", log_prefix: "Instance #{worker.name}"
    ssh.run(worker, settings.ssh_port, worker_install_script, settings.use_ssh_agent)
    log_line "...k3s has been deployed to worker #{worker.name}.", log_prefix: "Instance #{worker.name}"
  end

  private def master_install_script(master, master_count)
    server = ""
    datastore_endpoint = ""
    etcd_arguments = ""

    if settings.datastore.mode == "etcd"
      server = master == first_master ? " --cluster-init " : " --server https://#{api_server_ip_address(master_count)}:6443 "
      etcd_arguments = " --etcd-expose-metrics=true "
    else
      datastore_endpoint = " K3S_DATASTORE_ENDPOINT='#{settings.datastore.external_datastore_endpoint}' "
    end

    flannel_backend = find_flannel_backend
    extra_args = "#{kube_api_server_args_list} #{kube_scheduler_args_list} #{kube_controller_manager_args_list} #{kube_cloud_controller_manager_args_list} #{kubelet_args_list} #{kube_proxy_args_list}"
    taint = settings.schedule_workloads_on_masters ? " " : " --node-taint CriticalAddonsOnly=true:NoExecute "

    Crinja.render(MASTER_INSTALL_SCRIPT, {
      cluster_name: settings.cluster_name,
      k3s_version: settings.k3s_version,
      k3s_token: k3s_token,
      disable_flannel: settings.disable_flannel.to_s,
      flannel_backend: flannel_backend,
      taint: taint,
      extra_args: extra_args,
      server: server,
      tls_sans: generate_tls_sans(master_count),
      private_network_test_ip: settings.private_network_subnet.split(".")[0..2].join(".") + ".0",
      cluster_cidr: settings.cluster_cidr,
      service_cidr: settings.service_cidr,
      cluster_dns: settings.cluster_dns,
      datastore_endpoint: datastore_endpoint,
      etcd_arguments: etcd_arguments
    })
  end

  private def worker_install_script
    Crinja.render(WORKER_INSTALL_SCRIPT, {
      cluster_name: settings.cluster_name,
      k3s_token: k3s_token,
      k3s_version: settings.k3s_version,
      first_master_private_ip_address: first_master.private_ip_address,
      private_network_test_ip: settings.private_network_subnet.split(".")[0..2].join(".") + ".0",
      extra_args: kubelet_args_list
    })
  end

  private def find_flannel_backend
    return " " unless configuration.settings.enable_encryption

    available_releases = K3s.available_releases
    selected_k3s_index = available_releases.index(settings.k3s_version).not_nil!
    k3s_1_23_6_index = available_releases.index("v1.23.6+k3s1").not_nil!

    selected_k3s_index >= k3s_1_23_6_index ? " --flannel-backend=wireguard-native " : " --flannel-backend=wireguard "
  end

  private def kube_api_server_args_list
    kubernetes_component_args_list("kube-apiserver", settings.kube_api_server_args)
  end

  private def kube_scheduler_args_list
    kubernetes_component_args_list("kube-scheduler", settings.kube_scheduler_args)
  end

  private def kube_controller_manager_args_list
    kubernetes_component_args_list("kube-controller-manager", settings.kube_controller_manager_args)
  end

  private def kube_cloud_controller_manager_args_list
    kubernetes_component_args_list("kube-cloud-controller-manager", settings.kube_cloud_controller_manager_args)
  end

  private def kubelet_args_list
    kubernetes_component_args_list("kubelet", settings.all_kubelet_args)
  end

  private def kube_proxy_args_list
    kubernetes_component_args_list("kube-proxy", settings.kube_proxy_args)
  end

  private def k3s_token
    token = begin
      ssh.run(first_master, settings.ssh_port, "cat /var/lib/rancher/k3s/server/node-token", settings.use_ssh_agent, print_output: false)
    rescue
      ""
    end

    token.empty? ? Random::Secure.hex : token.split(':').last
  end

  private def save_kubeconfig(master_count)
    kubeconfig_path = configuration.kubeconfig_path

    log_line "Saving the kubeconfig file to #{kubeconfig_path}...", "Control plane"

    kubeconfig = ssh.run(first_master, settings.ssh_port, "cat /etc/rancher/k3s/k3s.yaml", settings.use_ssh_agent, print_output: false).
      gsub("127.0.0.1",  settings.api_server_hostname ? settings.api_server_hostname : api_server_ip_address(master_count)).
      gsub("default", settings.cluster_name)

    File.write(kubeconfig_path, kubeconfig)

    File.chmod kubeconfig_path, 0o600
  end

  private def add_labels_and_taints_to_masters
    add_labels_or_taints(:label, masters, settings.masters_pool.labels, :master)
    add_labels_or_taints(:taint, masters, settings.masters_pool.taints, :master)
  end

  private def add_labels_and_taints_to_workers
    settings.worker_node_pools.each do |node_pool|
      instance_type = node_pool.instance_type
      node_name_prefix = /#{settings.cluster_name}-#{instance_type}-pool-#{node_pool.name}-worker/

      nodes = workers.select { |worker| node_name_prefix =~ worker.name }

      add_labels_or_taints(:label, nodes, node_pool.labels, :worker)
      add_labels_or_taints(:taint, nodes, node_pool.taints, :worker)
    end
  end

  private def add_labels_or_taints(mark_type, instances, marks, instance_type)
    return unless marks.any?

    node_names = instances.map(&.name).join(" ")

    log_line "\nAdding #{mark_type}s to #{instance_type}s...", log_prefix: "Node labels"

    all_marks = marks.map do |mark|
      "#{mark.key}=#{mark.value}"
    end.join(" ")

    command = "kubectl #{mark_type} --overwrite nodes #{node_names} #{all_marks}"

    run_shell_command(command, configuration.kubeconfig_path, settings.hetzner_token, log_prefix: "Node labels")

    log_line "...node labels applied", log_prefix: "Node labels"
  end

  private def generate_tls_sans(master_count)
    sans = ["--tls-san=#{api_server_ip_address(master_count)}"]
    sans << "--tls-san=#{settings.api_server_hostname}" if settings.api_server_hostname
    sans << "--tls-san=#{load_balancer.not_nil!.private_ip_address}" if masters.size > 1

    masters.each do |master|
      master_private_ip = master.private_ip_address
      sans << "--tls-san=#{master_private_ip}"
    end
    sans.join(" ")
  end

  private def install_software
    Kubernetes::Software::Hetzner::Secret.new(configuration, settings).create
    Kubernetes::Software::Hetzner::CloudControllerManager.new(configuration, settings).install
    Kubernetes::Software::Hetzner::CSIDriver.new(configuration, settings).install
    Kubernetes::Software::SystemUpgradeController.new(configuration, settings).install
    Kubernetes::Software::ClusterAutoscaler.new(configuration, settings, first_master, ssh, autoscaling_worker_node_pools, worker_install_script).install
  end

  private def default_log_prefix
    "Kubernetes software"
  end

  private def first_master
    masters[0].not_nil!
  end

  private def api_server_ip_address(master_count)
    master_count > 1 ? load_balancer.not_nil!.public_ip_address.not_nil! : first_master.host_ip_address.not_nil!
  end
end
