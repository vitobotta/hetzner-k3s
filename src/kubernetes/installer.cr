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

  def self.worker_install_script(settings, masters, first_master, worker_pool)
    labels_and_taints = ::Kubernetes::Installer.labels_and_tains(settings, worker_pool)

    Crinja.render(WORKER_INSTALL_SCRIPT, {
      cluster_name: settings.cluster_name,
      k3s_token: k3s_token(settings, masters),
      k3s_version: settings.k3s_version,
      api_server_ip_address: api_server_ip_address(first_master),
      private_network_enabled: settings.networking.private_network.enabled.to_s,
      private_network_subnet: settings.networking.private_network.enabled ? settings.networking.private_network.subnet : "",
      cluster_cidr: settings.networking.cluster_cidr,
      service_cidr: settings.networking.service_cidr,
      extra_args: kubelet_args_list(settings),
      labels_and_taints: labels_and_taints
    })
  end

  def self.kubelet_args_list(settings)
    ::Kubernetes::Util.kubernetes_component_args_list("kubelet", settings.all_kubelet_args)
  end

  def self.labels_and_tains(settings, pool)
    pool = pool.not_nil!
    args = /^master-/ =~ pool.name ? settings.all_kubelet_args : [] of String

    labels = [] of String
     pool.labels.each do |label|
      next if label.key.nil? || label.value.nil?
      escaped_key = label.key.gsub('"', '\\"')
      escaped_value = label.value.gsub('"', '\\"')
      labels << "--node-label \"#{escaped_key}=#{escaped_value}\""
    end

    labels_args = " #{labels.join(" ")} " unless labels.empty?

    taints = [] of String
    pool.taints.each do |taint|
      next if taint.key.nil? || taint.value.nil?
      parts = taint.value.not_nil!.split(":")
      value = parts[0]
      effect = parts.size > 1 ? parts[1] : "NoSchedule"
      escaped_key = taint.key.not_nil!.gsub('"', '\\"')
      escaped_value = value.gsub('"', '\\"')
      taints << "--node-taint \"#{escaped_key}=#{escaped_value}:#{effect}\""
    end

    taint_args = " #{taints.join(" ")} " unless taints.empty?

    " #{labels_args} #{taint_args} "
  end

  def self.k3s_token(settings, masters)
    @@k3s_token ||= begin
      tokens = masters.map { |master| ::Kubernetes::Installer.token_by_master(settings, master) }.reject(&.empty?)

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

  def self.token_by_master(settings, master : Hetzner::Instance)
    ::Util::SSH.new(settings.networking.ssh.private_key_path, settings.networking.ssh.public_key_path)
      .run(master, settings.networking.ssh.port, "cat /var/lib/rancher/k3s/server/node-token", settings.networking.ssh.use_agent, print_output: false).split(':').last
  rescue
    ""
  end

  def self.api_server_ip_address(first_master)
    first_master.private_ip_address || first_master.public_ip_address
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
    end

    Kubernetes::Software::ClusterAutoscaler.new(configuration, settings, masters, first_master, ssh, autoscaling_worker_node_pools).install

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

        pool = settings.worker_node_pools.find do |pool|
          worker.name.split("-")[0..-2].join("-") =~ /^#{settings.cluster_name.to_s}-.*pool-#{pool.name.to_s}$/
        end

        deploy_k3s_to_worker(pool, worker)

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

  private def set_up_first_master(master_count : Int)
    ssh.run(first_master, settings.networking.ssh.port, CLOUD_INIT_WAIT_SCRIPT, settings.networking.ssh.use_agent)

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
    ssh.run(master, settings.networking.ssh.port, master_install_script(master, master_count), settings.networking.ssh.use_agent)
    log_line "...k3s deployed", log_prefix: "Instance #{master.name}"
  end

  private def deploy_k3s_to_worker(pool, worker : Hetzner::Instance)
    ssh.run(worker, settings.networking.ssh.port, CLOUD_INIT_WAIT_SCRIPT, settings.networking.ssh.use_agent)
    ssh.run(worker, settings.networking.ssh.port, ::Kubernetes::Installer.worker_install_script(settings, masters, first_master, pool), settings.networking.ssh.use_agent)
    log_line "...k3s has been deployed to worker #{worker.name}.", log_prefix: "Instance #{worker.name}"
  end

  private def master_install_script(master, master_count)
    server = ""
    datastore_endpoint = ""
    etcd_arguments = ""

    if settings.datastore.mode == "etcd"
      server = master == first_master ? " --cluster-init " : " --server https://#{::Kubernetes::Installer.api_server_ip_address(first_master)}:6443 "
      etcd_arguments = " --etcd-expose-metrics=true "
    else
      datastore_endpoint = " K3S_DATASTORE_ENDPOINT='#{settings.datastore.external_datastore_endpoint}' "
    end

    extra_args = "#{kube_api_server_args_list} #{kube_scheduler_args_list} #{kube_controller_manager_args_list} #{kube_cloud_controller_manager_args_list} #{::Kubernetes::Installer.kubelet_args_list(settings)} #{kube_proxy_args_list}"
    master_taint = settings.schedule_workloads_on_masters ? " " : " --node-taint CriticalAddonsOnly=true:NoExecute "
    labels_and_taints = ::Kubernetes::Installer.labels_and_tains(settings, settings.masters_pool)

    Crinja.render(MASTER_INSTALL_SCRIPT, {
      cluster_name: settings.cluster_name,
      k3s_version: settings.k3s_version,
      k3s_token: ::Kubernetes::Installer.k3s_token(settings, masters),
      cni: cni.enabled.to_s,
      cni_mode: cni.mode,
      flannel_backend: flannel_backend,
      master_taint: master_taint,
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
      local_path_storage_class_enabled: settings.local_path_storage_class.enabled.to_s,
      labels_and_taints: labels_and_taints
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

  private def kube_proxy_args_list
    kubernetes_component_args_list("kube-proxy", settings.kube_proxy_args)
  end

  private def first_master : Hetzner::Instance
    @first_master ||= begin
      token = ::Kubernetes::Installer.k3s_token(settings, masters)
      return masters[0] if token.empty?

      bootstrapped_master = masters.sort_by(&.name).find { |master| ::Kubernetes::Installer.token_by_master(settings, master) == token }
      bootstrapped_master || masters[0]
    end
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

  private def generate_tls_sans(master_count)
    sans = ["--tls-san=#{::Kubernetes::Installer.api_server_ip_address(first_master)}", "--tls-san=127.0.0.1"]
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

  private def load_balancer_ip_address
    load_balancer.try(&.public_ip_address)
  end

  private def default_context
    load_balancer.nil? ? first_master.name : settings.cluster_name
  end
end
