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
require "./software/cilium"
require "./software/hetzner/secret"
require "./software/hetzner/cloud_controller_manager"
require "./software/hetzner/csi_driver"
require "./software/cluster_autoscaler"

class Kubernetes::Installer
  include Util
  include Util::Shell

  MASTER_INSTALL_SCRIPT = {{ read_file("#{__DIR__}/../../templates/master_install_script.sh") }}
  WORKER_INSTALL_SCRIPT = {{ read_file("#{__DIR__}/../../templates/worker_install_script.sh") }}
  CLOUD_INIT_WAIT_SCRIPT = {{ read_file("#{__DIR__}/../../templates/cloud_init_wait_script.sh") }}

  getter configuration : Configuration::Loader
  getter settings : Configuration::Main { configuration.settings }
  getter masters : Array(Hetzner::Instance) = [] of Hetzner::Instance
  getter workers : Array(Hetzner::Instance) = [] of Hetzner::Instance
  getter autoscaling_worker_node_pools : Array(Configuration::NodePool)
  getter load_balancer : Hetzner::LoadBalancer?
  getter ssh : ::Util::SSH

  private getter first_master : Hetzner::Instance?

  private getter cni : Configuration::NetworkingComponents::CNI { settings.networking.cni }

  def initialize(
      @configuration,
      # @load_balancer,
      @ssh,
      @autoscaling_worker_node_pools
    )
  end

  def run(masters_installation_queue_channel, workers_installation_queue_channel, completed_channel, master_count, worker_count)
    ensure_kubectl_is_installed!

    set_up_control_plane(masters_installation_queue_channel, master_count)

    save_kubeconfig(master_count)

    install_software(master_count)

    set_up_workers(workers_installation_queue_channel, worker_count, master_count)

    add_labels_and_taints_to_masters
    add_labels_and_taints_to_workers

    completed_channel.send(nil)
  end

  private def set_up_control_plane(masters_installation_queue_channel, master_count)
    master_count.times do
      masters << masters_installation_queue_channel.receive
    end

    masters_ready_channel = Channel(Hetzner::Instance).new

    set_up_first_master(master_count)

    other_masters = masters - [first_master]

    other_masters.each do |master|
      spawn do
        deploy_k3s_to_master(master, master_count)
        masters_ready_channel.send(master)
      end
    end

    (master_count - 1).times do
      masters_ready_channel.receive
    end
  end

  private def set_up_workers(workers_installation_queue_channel, worker_count, master_count)
    workers_ready_channel = Channel(Hetzner::Instance).new

    mutex = Mutex.new

    worker_count.times do
      spawn do
        worker = workers_installation_queue_channel.receive
        mutex.synchronize { workers << worker }
        deploy_k3s_to_worker(worker, master_count)
        workers_ready_channel.send(worker)
      end
    end

    worker_count.times do
      workers_ready_channel.receive
    end
  end

  private def set_up_first_master(master_count : Int)
    ssh.run(first_master, settings.networking.ssh.port, CLOUD_INIT_WAIT_SCRIPT, settings.networking.ssh.use_agent)

    install_script = master_install_script(first_master, master_count)

    output = ssh.run(first_master, settings.networking.ssh.port, install_script, settings.networking.ssh.use_agent)

    log_line  "Waiting for the control plane to be ready...", log_prefix: "Instance #{first_master.name}"

    sleep 10 unless /No change detected/ =~ output

    save_kubeconfig(master_count)

    sleep 5

    command = "kubectl cluster-info 2> /dev/null"

    Retriable.retry(max_attempts: 3, on: Tasker::Timeout, backoff: false) do
      Tasker.timeout(30.seconds) do
        loop do
          result = run_shell_command(command, configuration.kubeconfig_path, settings.hetzner_token, log_prefix: "Control plane", abort_on_error: false, print_output: false)
          break if result.output.includes?("running")
          sleep 1
        end
      end
    end

    log_line "...k3s deployed", log_prefix: "Instance #{first_master.name}"
  end

  private def deploy_k3s_to_master(master : Hetzner::Instance, master_count)
    ssh.run(master, settings.networking.ssh.port, CLOUD_INIT_WAIT_SCRIPT, settings.networking.ssh.use_agent)

    install_script = master_install_script(master, master_count)
    ssh.run(master, settings.networking.ssh.port, install_script, settings.networking.ssh.use_agent)
    log_line "...k3s deployed", log_prefix: "Instance #{master.name}"
  end

  private def deploy_k3s_to_worker(worker : Hetzner::Instance, master_count)
    ssh.run(worker, settings.networking.ssh.port, CLOUD_INIT_WAIT_SCRIPT, settings.networking.ssh.use_agent)

    install_script = worker_install_script(master_count)
    ssh.run(worker, settings.networking.ssh.port, install_script, settings.networking.ssh.use_agent)
    log_line "...k3s has been deployed to worker #{worker.name}.", log_prefix: "Instance #{worker.name}"
  end

  private def master_install_script(master, master_count)
    server = ""
    datastore_endpoint = ""
    etcd_arguments = ""

    if settings.datastore.mode == "etcd"
      server = master == first_master ? " --cluster-init " : " --server https://#{api_server_ip_address}:6443 "
      etcd_arguments = " --etcd-expose-metrics=true "
    else
      datastore_endpoint = " K3S_DATASTORE_ENDPOINT='#{settings.datastore.external_datastore_endpoint}' "
    end

    extra_args = "#{kube_api_server_args_list} #{kube_scheduler_args_list} #{kube_controller_manager_args_list} #{kube_cloud_controller_manager_args_list} #{kubelet_args_list} #{kube_proxy_args_list}"
    taint = settings.schedule_workloads_on_masters ? " " : " --node-taint CriticalAddonsOnly=true:NoExecute "

    Crinja.render(MASTER_INSTALL_SCRIPT, {
      cluster_name: settings.cluster_name,
      k3s_version: settings.k3s_version,
      k3s_token: k3s_token,
      cni: cni.enabled.to_s,
      cni_mode: cni.mode,
      flannel_backend: flannel_backend,
      taint: taint,
      extra_args: extra_args,
      server: server,
      tls_sans: generate_tls_sans(master_count),
      private_network_enabled: settings.networking.private_network.enabled.to_s,
      private_network_test_ip: settings.networking.private_network.subnet.split(".")[0..2].join(".") + ".0",
      private_network_subnet: settings.networking.private_network.enabled ? settings.networking.private_network.subnet : "",
      cluster_cidr: settings.networking.cluster_cidr,
      service_cidr: settings.networking.service_cidr,
      cluster_dns: settings.networking.cluster_dns,
      datastore_endpoint: datastore_endpoint,
      etcd_arguments: etcd_arguments,
      s3_arguments: generate_s3_arguments(),
      embedded_registry_mirror_enabled: settings.embedded_registry_mirror.enabled.to_s,
    })
  end

  private def worker_install_script(master_count)
    Crinja.render(WORKER_INSTALL_SCRIPT, {
      cluster_name: settings.cluster_name,
      k3s_token: k3s_token,
      k3s_version: settings.k3s_version,
      api_server_ip_address: api_server_ip_address,
      private_network_enabled: settings.networking.private_network.enabled.to_s,
      private_network_test_ip: settings.networking.private_network.subnet.split(".")[0..2].join(".") + ".0",
      private_network_subnet: settings.networking.private_network.enabled ? settings.networking.private_network.subnet : "",
      extra_args: kubelet_args_list
    })
  end

  private def flannel_backend
    if cni.flannel? && cni.encryption?
      available_releases = K3s.available_releases
      selected_k3s_index = available_releases.index(settings.k3s_version).not_nil!
      k3s_1_23_6_index = available_releases.index("v1.23.6+k3s1").not_nil!

      selected_k3s_index >= k3s_1_23_6_index ? " --flannel-backend=wireguard-native " : " --flannel-backend=wireguard "
    elsif cni.flannel?
      " "
    else
      args = [
        "--flannel-backend=none",
        "--disable-network-policy"
      ]

      args << "--disable-kube-proxy" unless cni.kube_proxy?
      args.join(" ")
    end
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

  private def k3s_token : String
    @k3s_token ||= begin
      tokens = masters.map do |master|
        token_by_master(master)
      end.reject(&.empty?)

      if tokens.empty?
        Random::Secure.hex
      else
        tokens = tokens.tally
        max_counts = tokens.max_of { |_, count| count }
        token = tokens.key_for(max_counts)
        token.empty? ? Random::Secure.hex : token.split(':').last
      end
    end
  end

  private def first_master : Hetzner::Instance
    @first_master ||= begin
      return masters[0] if k3s_token.empty?

      bootstrapped_master = masters.sort_by(&.name).find do |master|
        token_by_master(master) == k3s_token
      end

      bootstrapped_master || masters[0]
    end
  end

  private def token_by_master(master : Hetzner::Instance)
    ssh.run(master, settings.networking.ssh.port, "cat /var/lib/rancher/k3s/server/node-token", settings.networking.ssh.use_agent, print_output: false).split(':').last
  rescue
    ""
  end

  private def save_kubeconfig(master_count)
    kubeconfig_path = configuration.kubeconfig_path

    log_line "Generating the kubeconfig file to #{kubeconfig_path}...", "Control plane"

    kubeconfig = ssh.run(first_master, settings.networking.ssh.port, "cat /etc/rancher/k3s/k3s.yaml", settings.networking.ssh.use_agent, print_output: false).
      gsub("default", settings.cluster_name)

    File.write(kubeconfig_path, kubeconfig)

    masters.each_with_index do |master, index|
      master_ip_address = settings.networking.public_network.ipv4 ? master.public_ip_address : master.private_ip_address
      master_kubeconfig_path = "#{kubeconfig_path}-#{master.name}"
      master_kubeconfig = kubeconfig
        .gsub("server: https://127.0.0.1:6443", "server: https://#{master_ip_address}:6443")
        .gsub("name: #{settings.cluster_name}", "name: #{master.name}")
        .gsub("cluster: #{settings.cluster_name}", "cluster: #{master.name}")
        .gsub("user: #{settings.cluster_name}", "user: #{master.name}")
        .gsub("current-context: #{settings.cluster_name}", "current-context: #{master.name}")

      File.write(master_kubeconfig_path, master_kubeconfig)
    end

    paths = masters.map { |master| "#{kubeconfig_path}-#{master.name}" }.join(":")

    system("KUBECONFIG=#{paths} kubectl config view --flatten > #{kubeconfig_path}")
    system("KUBECONFIG=#{kubeconfig_path} kubectl config use-context #{first_master.name}")

    masters.each do |master|
      FileUtils.rm("#{kubeconfig_path}-#{master.name}")
    end

    File.chmod kubeconfig_path, 0o600

    log_line "...kubeconfig file generated as #{kubeconfig_path}.", "Control plane"
  end

  private def add_labels_and_taints_to_masters
    add_labels_or_taints(:label, masters, settings.masters_pool.labels, "masters_pool")
    add_labels_or_taints(:taint, masters, settings.masters_pool.taints, "masters_pool")
  end

  private def add_labels_and_taints_to_workers
    settings.worker_node_pools.each do |node_pool|
      instance_type = node_pool.instance_type
      node_name_prefix = /#{settings.cluster_name}-pool-#{node_pool.name}-worker/

      nodes = workers.select { |worker| node_name_prefix =~ worker.name }

      add_labels_or_taints(:label, nodes, node_pool.labels, node_pool.name)
      add_labels_or_taints(:taint, nodes, node_pool.taints, node_pool.name)
    end
  end

  private def add_labels_or_taints(mark_type, instances, marks, node_pool_name)
    return unless marks.any?

    node_names = instances.map(&.name).join(" ")

    log_line "\nAdding #{mark_type}s to #{node_pool_name} pool workers...", log_prefix: "Node labels"

    all_marks = marks.map do |mark|
      "#{mark.key}=#{mark.value}"
    end.join(" ")

    command = "kubectl #{mark_type} --overwrite nodes #{node_names} #{all_marks}"

    run_shell_command(command, configuration.kubeconfig_path, settings.hetzner_token, log_prefix: "Node labels")

    log_line "...node labels applied", log_prefix: "Node labels"
  end

  private def generate_tls_sans(master_count)
    sans = [
      "--tls-san=#{api_server_ip_address}",
      "--tls-san=127.0.0.1"
    ]
    sans << "--tls-san=#{settings.api_server_hostname}" if settings.api_server_hostname

    masters.each do |master|
      master_private_ip = master.private_ip_address
      master_public_ip = master.public_ip_address
      sans << "--tls-san=#{master_private_ip}"
      sans << "--tls-san=#{master_public_ip}"
    end

    sans.uniq.sort.join(" ")
  end

  private def install_software(master_count)
    Kubernetes::Software::Cilium.new(configuration, settings).install if settings.networking.cni.cilium?
    Kubernetes::Software::Hetzner::Secret.new(configuration, settings).create
    Kubernetes::Software::Hetzner::CloudControllerManager.new(configuration, settings).install
    Kubernetes::Software::Hetzner::CSIDriver.new(configuration, settings).install
    Kubernetes::Software::SystemUpgradeController.new(configuration, settings).install
    Kubernetes::Software::ClusterAutoscaler.new(configuration, settings, first_master, ssh, autoscaling_worker_node_pools, worker_install_script(master_count)).install
  end

  private def default_log_prefix
    "Kubernetes software"
  end

  private def api_server_ip_address
    if first_master.private_ip_address.nil?
      first_master.public_ip_address
    else
      first_master.private_ip_address
    end
  end

  private def generate_s3_arguments
    opts = [] of String

    opts << "--etcd-s3" if settings.datastore.s3.enabled
    opts << "--etcd-s3-endpoint=#{settings.datastore.s3.endpoint}" if present?(settings.datastore.s3.endpoint)
    opts << "--etcd-s3-endpoint-ca=#{settings.datastore.s3.endpoint_ca}" if present?(settings.datastore.s3.endpoint_ca)
    opts << "--etcd-s3-skip-ssl-verify" if settings.datastore.s3.skip_ssl_verify
    opts << "--etcd-s3-access-key=#{settings.datastore.s3.access_key}" if present?(settings.datastore.s3.access_key)
    opts << "--etcd-s3-secret-key=#{settings.datastore.s3.secret_key}" if present?(settings.datastore.s3.secret_key)
    opts << "--etcd-s3-bucket=#{settings.datastore.s3.bucket}" if present?(settings.datastore.s3.bucket)
    opts << "--etcd-s3-region=#{settings.datastore.s3.region}" if present?(settings.datastore.s3.region)
    opts << "--etcd-s3-folder=#{settings.datastore.s3.folder}" if present?(settings.datastore.s3.folder)
    opts << "--etcd-s3-insecure" if settings.datastore.s3.insecure
    opts << "--etcd-s3-timeout=#{settings.datastore.s3.timeout}" if present?(settings.datastore.s3.timeout)

    opts.uniq.sort.join(" ")
  end
end
