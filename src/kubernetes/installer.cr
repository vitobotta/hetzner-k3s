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
  FIREWALL_SETUP_SCRIPT = {{ read_file("#{__DIR__}/../../templates/firewall_setup_script.sh") }}

  getter configuration : Configuration::Loader
  getter settings : Configuration::Main { configuration.settings }
  getter masters : Array(Hetzner::Instance) = [] of Hetzner::Instance
  getter workers : Array(Hetzner::Instance) = [] of Hetzner::Instance
  getter autoscaling_worker_node_pools : Array(Configuration::WorkerNodePool)
  getter load_balancer : Hetzner::LoadBalancer?
  getter ssh : ::Util::SSH

  private getter first_master : Hetzner::Instance?
  private getter cni : Configuration::NetworkingComponents::CNI { settings.networking.cni }

  def initialize(
      @configuration,
      @load_balancer,
      @ssh,
      @autoscaling_worker_node_pools
    )
  end

  def run(masters_installation_queue_channel, workers_installation_queue_channel, completed_channel, master_count, worker_count)
    ensure_kubectl_is_installed!

    set_up_control_plane(masters_installation_queue_channel, master_count)

    save_kubeconfig(master_count)

    Kubernetes::Software::Cilium.new(configuration, settings).install if settings.networking.cni.enabled? && settings.networking.cni.cilium?

    Kubernetes::Software::Hetzner::Secret.new(configuration, settings).create
    Kubernetes::Software::Hetzner::CloudControllerManager.new(configuration, settings).install
    Kubernetes::Software::Hetzner::CSIDriver.new(configuration, settings).install

    Kubernetes::Software::SystemUpgradeController.new(configuration, settings).install

    if worker_count > 0
      set_up_workers(workers_installation_queue_channel, worker_count, master_count)
      add_labels_and_taints
    end

    Kubernetes::Software::ClusterAutoscaler.new(configuration, settings, first_master, ssh, autoscaling_worker_node_pools, worker_install_script).install

    switch_to_context(default_context)

    completed_channel.send(nil)
  end

  private def set_up_control_plane(masters_installation_queue_channel, master_count)
    master_count.times { masters << masters_installation_queue_channel.receive }
    masters_ready_channel = Channel(Hetzner::Instance).new

    set_up_first_master(master_count)

    (masters - [first_master]).each do |master|
      spawn do
        deploy_k3s_to_master(master, master_count)
        masters_ready_channel.send(master)
      end
    end

    (master_count - 1).times { masters_ready_channel.receive }
  end

  private def set_up_workers(workers_installation_queue_channel, worker_count, master_count)
    workers_ready_channel = Channel(Hetzner::Instance).new
    semaphore = Channel(Nil).new(10)
    mutex = Mutex.new

    worker_count.times do
      semaphore.send(nil)
      spawn do
        worker = workers_installation_queue_channel.receive
        mutex.synchronize { workers << worker }
        deploy_k3s_to_worker(worker)
        semaphore.receive
        workers_ready_channel.send(worker)
      end
    end

    worker_count.times { workers_ready_channel.receive }

    wait_for_one_worker_to_be_ready
  end

  private def wait_for_one_worker_to_be_ready
    log_line "Waiting for at least one worker node to be ready...", log_prefix: "Cluster Autoscaler"

    timeout = Time.monotonic + 5.minutes

    loop do
      output = ssh.run(first_master, settings.networking.ssh.port, "KUBECONFIG=/etc/rancher/k3s/k3s.yaml kubectl get nodes", settings.networking.ssh.use_agent, print_output: false)

      ready_workers = output.lines.count { |line| line.includes?("worker") && line.includes?("Ready") }

      break if ready_workers > 0

      if Time.monotonic > timeout
        log_line "Timeout waiting for worker nodes, aborting" , log_prefix: "Cluster Autoscaler"
        exit 1
      end

      sleep 5.seconds
    end
  end

  private def set_up_firewall(instance)
    return if settings.networking.private_network.enabled

    log_line  "Setting up fireall...", log_prefix: "Instance #{instance.name}"

    settings.networking.allowed_networks.api.each do |network|
      ssh.run(instance, settings.networking.ssh.port, "echo '#{network}' >> /root/allowed_networks.conf", settings.networking.ssh.use_agent)
    end

    firewall_setup_script = Crinja.render(FIREWALL_SETUP_SCRIPT, {
      hetzner_token: settings.hetzner_token,
      ips_query_server_url: settings.networking.public_network.ips_query_server_url
    })

    ssh.run(instance, settings.networking.ssh.port, firewall_setup_script, settings.networking.ssh.use_agent)

    sleep 5
  end

  private def set_up_first_master(master_count : Int)
    ssh.run(first_master, settings.networking.ssh.port, CLOUD_INIT_WAIT_SCRIPT, settings.networking.ssh.use_agent)

    set_up_firewall(first_master)

    install_script = master_install_script(first_master, master_count)

    output = ssh.run(first_master, settings.networking.ssh.port, install_script, settings.networking.ssh.use_agent)

    log_line  "Waiting for the control plane to be ready...", log_prefix: "Instance #{first_master.name}"

    sleep 10.seconds unless /No change detected/ =~ output

    save_kubeconfig(master_count)

    sleep 5.seconds

    command = "kubectl cluster-info 2> /dev/null"

    Retriable.retry(max_attempts: 3, on: Tasker::Timeout, backoff: false) do
      Tasker.timeout(30.seconds) do
        loop do
          result = run_shell_command(command, configuration.kubeconfig_path, settings.hetzner_token, log_prefix: "Control plane", abort_on_error: false, print_output: false)
          break if result.output.includes?("running")
          sleep 1.seconds
        end
      end
    end

    log_line "...k3s deployed", log_prefix: "Instance #{first_master.name}"
  end

  private def deploy_k3s_to_master(master : Hetzner::Instance, master_count)
    ssh.run(master, settings.networking.ssh.port, CLOUD_INIT_WAIT_SCRIPT, settings.networking.ssh.use_agent)
    set_up_firewall(master)
    ssh.run(master, settings.networking.ssh.port, master_install_script(master, master_count), settings.networking.ssh.use_agent)
    log_line "...k3s deployed", log_prefix: "Instance #{master.name}"
  end

  private def deploy_k3s_to_worker(worker : Hetzner::Instance)
    ssh.run(worker, settings.networking.ssh.port, CLOUD_INIT_WAIT_SCRIPT, settings.networking.ssh.use_agent)
    set_up_firewall(worker)
    ssh.run(worker, settings.networking.ssh.port, worker_install_script, settings.networking.ssh.use_agent)
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
      private_network_subnet: settings.networking.private_network.enabled ? settings.networking.private_network.subnet : "",
      cluster_cidr: settings.networking.cluster_cidr,
      service_cidr: settings.networking.service_cidr,
      cluster_dns: settings.networking.cluster_dns,
      datastore_endpoint: datastore_endpoint,
      etcd_arguments: etcd_arguments,
      embedded_registry_mirror_enabled: settings.embedded_registry_mirror.enabled.to_s,
      local_path_storage_class_enabled: settings.local_path_storage_class.enabled.to_s
    })
  end

  private def worker_install_script
    Crinja.render(WORKER_INSTALL_SCRIPT, {
      cluster_name: settings.cluster_name,
      k3s_token: k3s_token,
      k3s_version: settings.k3s_version,
      api_server_ip_address: api_server_ip_address,
      private_network_enabled: settings.networking.private_network.enabled.to_s,
      private_network_subnet: settings.networking.private_network.enabled ? settings.networking.private_network.subnet : "",
      cluster_cidr: settings.networking.cluster_cidr,
      service_cidr: settings.networking.service_cidr,
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
      args = ["--flannel-backend=none", "--disable-network-policy"]
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
      tokens = masters.map { |master| token_by_master(master) }.reject(&.empty?)

      if tokens.empty?
        Random::Secure.hex
      else
        tokens = tokens.tally
        max_quorum = tokens.max_of { |_, count| count }
        token = tokens.key_for(max_quorum)
        token.empty? ? Random::Secure.hex : token.split(':').last
      end
    end
  end

  private def first_master : Hetzner::Instance
    @first_master ||= begin
      return masters[0] if k3s_token.empty?

      bootstrapped_master = masters.sort_by(&.name).find { |master| token_by_master(master) == k3s_token }
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

    if settings.create_load_balancer_for_the_kubernetes_api
      load_balancer_kubeconfig_path = "#{kubeconfig_path}-#{settings.cluster_name}"
      load_balancer_kubeconfig = kubeconfig.gsub("server: https://127.0.0.1:6443", "server: https://#{load_balancer_ip_address}:6443")

      File.write(load_balancer_kubeconfig_path, load_balancer_kubeconfig)
    end

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

    paths = settings.create_load_balancer_for_the_kubernetes_api ? [load_balancer_kubeconfig_path] : [] of String

    paths = (paths + masters.map { |master| "#{kubeconfig_path}-#{master.name}" }).join(":")

    run_shell_command("KUBECONFIG=#{paths} kubectl config view --flatten > #{kubeconfig_path}", "", settings.hetzner_token, log_prefix: "Control plane")

    switch_to_context(first_master.name)

    masters.each do |master|
      FileUtils.rm("#{kubeconfig_path}-#{master.name}")
    end

    File.chmod kubeconfig_path, 0o600

    log_line "...kubeconfig file generated as #{kubeconfig_path}.", "Control plane"
  end

  private def add_labels_and_taints
    add_labels_or_taints(:label, masters, settings.masters_pool.labels, "masters_pool")
    add_labels_or_taints(:taint, masters, settings.masters_pool.taints, "masters_pool")

    settings.worker_node_pools.each do |node_pool|
      nodes = workers.select { |worker| /#{settings.cluster_name}-pool-#{node_pool.name}-worker/ =~ worker.name }
      add_labels_or_taints(:label, nodes, node_pool.labels, node_pool.name)
      add_labels_or_taints(:taint, nodes, node_pool.taints, node_pool.name)
    end
  end

  private def add_labels_or_taints(mark_type, instances, marks, node_pool_name)
    return unless marks.any?

    node_names = instances.map(&.name).join(" ")

    log_line "\nAdding #{mark_type}s to #{node_pool_name} pool workers...", log_prefix: "Node labels"

    all_marks = marks.map { |mark| "#{mark.key}=#{mark.value}" }.join(" ")
    command = "kubectl #{mark_type} --overwrite nodes #{node_names} #{all_marks}"

    run_shell_command(command, configuration.kubeconfig_path, settings.hetzner_token, log_prefix: "Node labels")

    log_line "...node labels applied", log_prefix: "Node labels"
  end

  private def generate_tls_sans(master_count)
    sans = ["--tls-san=#{api_server_ip_address}", "--tls-san=127.0.0.1"]
    sans << "--tls-san=#{load_balancer_ip_address}" if settings.create_load_balancer_for_the_kubernetes_api
    sans << "--tls-san=#{settings.api_server_hostname}" if settings.api_server_hostname

    masters.each do |master|
      sans << "--tls-san=#{master.private_ip_address}"
      sans << "--tls-san=#{master.public_ip_address}"
    end

    sans.uniq.sort.join(" ")
  end

  private def default_log_prefix
    "Kubernetes software"
  end

  private def api_server_ip_address
    first_master.private_ip_address || first_master.public_ip_address
  end

  private def load_balancer_ip_address
    load_balancer.try(&.public_ip_address)
  end

  private def default_context
    load_balancer.nil? ? first_master.name : settings.cluster_name
  end
end
