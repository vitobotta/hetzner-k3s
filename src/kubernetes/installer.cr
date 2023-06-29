require "crinja"
require "base64"
require "../util"
require "../util/ssh"
require "../util/shell"
require "../hetzner/server"
require "../hetzner/load_balancer"
require "../configuration/loader"
require "file_utils"

class Kubernetes::Installer
  MASTER_INSTALL_SCRIPT = {{ read_file("#{__DIR__}/../../templates/master_install_script.sh") }}
  WORKER_INSTALL_SCRIPT = {{ read_file("#{__DIR__}/../../templates/worker_install_script.sh") }}
  HETZNER_CLOUD_SECRET_MANIFEST = {{ read_file("#{__DIR__}/../../templates/hetzner_cloud_secret_manifest.yaml") }}
  CLUSTER_AUTOSCALER_MANIFEST = {{ read_file("#{__DIR__}/../../templates/cluster_autoscaler.yaml") }}

  getter configuration : Configuration::Loader
  getter settings : Configuration::Main { configuration.settings }
  getter masters : Array(Hetzner::Server)
  getter workers : Array(Hetzner::Server)
  getter autoscaling_worker_node_pools : Array(Configuration::NodePool)
  getter load_balancer : Hetzner::LoadBalancer?
  getter ssh : Util::SSH

  getter first_master : Hetzner::Server { masters[0] }
  getter api_server_ip_address : String { masters.size > 1 ? load_balancer.not_nil!.public_ip_address.not_nil! : first_master.public_ip_address.not_nil! }
  getter tls_sans : String { generate_tls_sans }

  def initialize(@configuration, @masters, @workers, @load_balancer, @ssh, @autoscaling_worker_node_pools)
  end

  def run
    puts "\n=== Setting up Kubernetes ===\n"

    set_up_first_master
    set_up_other_masters
    set_up_workers

    puts "\n=== Deploying Hetzner drivers ===\n"

    Util.check_kubectl

    add_labels_and_taints_to_masters
    add_labels_and_taints_to_workers

    create_hetzner_cloud_secret
    deploy_cloud_controller_manager
    deploy_csi_driver
    deploy_system_upgrade_controller
    deploy_cluster_autoscaler unless autoscaling_worker_node_pools.size.zero?
  end

  private def set_up_first_master
    puts "Deploying k3s to first master #{first_master.name}..."

    output = ssh.run(first_master, settings.ssh_port, master_install_script(first_master), settings.use_ssh_agent)

    puts "Waiting for the control plane to be ready..."

    sleep 10 unless /No change detected/ =~ output

    save_kubeconfig

    puts "...k3s has been deployed to first master #{first_master.name} and the control plane is up."
  end

  private def set_up_other_masters
    channel = Channel(Hetzner::Server).new
    other_masters = masters[1..-1]

    deploy_masters_in_parallel(channel, other_masters)
    wait_for_masters_deployment(channel, other_masters.size)
  end

  private def deploy_masters_in_parallel(channel : Channel(Hetzner::Server), other_masters : Array(Hetzner::Server))
    other_masters.each do |master|
      spawn do
        deploy_k3s_to_master(master)
        channel.send(master)
      end
    end
  end

  private def deploy_k3s_to_master(master : Hetzner::Server)
    puts "Deploying k3s to master #{master.name}..."
    ssh.run(master, settings.ssh_port, master_install_script(master), settings.use_ssh_agent)
    puts "...k3s has been deployed to master #{master.name}."
  end

  private def wait_for_masters_deployment(channel : Channel(Hetzner::Server), num_masters : Int32)
    num_masters.times { channel.receive }
  end

  private def set_up_workers
    channel = Channel(Hetzner::Server).new

    deploy_workers_in_parallel(channel, workers)
    wait_for_workers_deployment(channel, workers.size)
  end

  private def deploy_workers_in_parallel(channel : Channel(Hetzner::Server), workers : Array(Hetzner::Server))
    workers.each do |worker|
      spawn do
        deploy_k3s_to_worker(worker)
        channel.send(worker)
      end
    end
  end

  private def deploy_k3s_to_worker(worker : Hetzner::Server)
    puts "Deploying k3s to worker #{worker.name}..."
    ssh.run(worker, settings.ssh_port, worker_install_script, settings.use_ssh_agent)
    puts "...k3s has been deployed to worker #{worker.name}."
  end

  private def wait_for_workers_deployment(channel : Channel(Hetzner::Server), num_workers : Int32)
    num_workers.times { channel.receive }
  end

  private def master_install_script(master)
    server = master == first_master ? " --cluster-init " : " --server https://#{api_server_ip_address}:6443 "
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
      tls_sans: tls_sans,
      private_network_test_ip: settings.private_network_subnet.split(".")[0..2].join(".") + ".1"
    })
  end

  private def worker_install_script
    Crinja.render(WORKER_INSTALL_SCRIPT, {
      cluster_name: settings.cluster_name,
      k3s_token: k3s_token,
      k3s_version: settings.k3s_version,
      first_master_private_ip_address: first_master.private_ip_address,
      private_network_test_ip: settings.private_network_subnet.split(".")[0..2].join(".") + ".1"
    })
  end

  private def find_flannel_backend
    return " " unless configuration.settings.enable_encryption

    available_releases = K3s.available_releases
    selected_k3s_index = available_releases.index(settings.k3s_version).not_nil!
    k3s_1_23_6_index = available_releases.index("v1.23.6+k3s1").not_nil!

    selected_k3s_index >= k3s_1_23_6_index ? " --flannel-backend=wireguard-native " : " --flannel-backend=wireguard "
  end

  private def args_list(settings_group, setting)
    setting.map { |arg| " --#{settings_group}-arg=\"#{arg}\" " }.join
  end

  private def kube_api_server_args_list
    args_list("kube-apiserver", settings.kube_api_server_args)
  end

  private def kube_scheduler_args_list
    args_list("kube-scheduler", settings.kube_scheduler_args)
  end

  private def kube_controller_manager_args_list
    args_list("kube-controller-manager", settings.kube_controller_manager_args)
  end

  private def kube_cloud_controller_manager_args_list
    args_list("kube-cloud-controller-manager", settings.kube_cloud_controller_manager_args)
  end

  private def kubelet_args_list
    args_list("kubelet", settings.kubelet_args)
  end

  private def kube_proxy_args_list
    args_list("kube-proxy", settings.kube_proxy_args)
  end

  private def k3s_token
    token = begin
      ssh.run(first_master, settings.ssh_port, "cat /var/lib/rancher/k3s/server/node-token", settings.use_ssh_agent, print_output: false)
    rescue
      ""
    end

    token.empty? ? Random::Secure.hex : token.split(':').last
  end

  private def save_kubeconfig
    kubeconfig_path = configuration.kubeconfig_path

    puts "Saving the kubeconfig file to #{kubeconfig_path}..."

    kubeconfig = ssh.run(first_master, settings.ssh_port, "cat /etc/rancher/k3s/k3s.yaml", settings.use_ssh_agent, print_output: false).
      gsub("127.0.0.1", api_server_ip_address).
      gsub("default", settings.cluster_name)

    File.write(kubeconfig_path, kubeconfig)

    File.chmod kubeconfig_path, 0o600
  end

  private def create_hetzner_cloud_secret
    puts "\nCreating secret for Hetzner Cloud token..."

    secret_manifest = Crinja.render(HETZNER_CLOUD_SECRET_MANIFEST, {
      network: (settings.existing_network || settings.cluster_name),
      token: settings.hetzner_token
    })

    command = <<-BASH
    kubectl apply -f - <<-EOF
    #{secret_manifest}
    EOF
    BASH

    result = Util::Shell.run(command, configuration.kubeconfig_path, settings.hetzner_token)

    unless result.success?
      puts "Failed to create Hetzner Cloud secret:"
      puts result
      exit 1
    end

    puts "...secret created."
  end

  private def deploy_cloud_controller_manager
    puts "\nDeploying Hetzner Cloud Controller Manager..."

    command = "kubectl apply -f #{settings.cloud_controller_manager_manifest_url}"

    result = Util::Shell.run(command, configuration.kubeconfig_path, settings.hetzner_token)

    unless result.success?
      puts "Failed to deploy Cloud Controller Manager:"
      puts result
      exit 1
    end

    puts "...Cloud Controller Manager deployed"
  end

  private def deploy_csi_driver
    puts "\nDeploying Hetzner CSI Driver..."

    command = "kubectl apply -f #{settings.csi_driver_manifest_url}"

    result = Util::Shell.run(command, configuration.kubeconfig_path, settings.hetzner_token)

    unless result.success?
      puts "Failed to deploy CSI Driver:"
      puts result
      exit 1
    end

    puts "...CSI Driver deployed"
  end

  private def deploy_system_upgrade_controller
    puts "\nDeploying k3s System Upgrade Controller..."

    command = "kubectl apply -f #{settings.system_upgrade_controller_manifest_url}"

    result = Util::Shell.run(command, configuration.kubeconfig_path, settings.hetzner_token)

    unless result.success?
      puts "Failed to deploy k3s System Upgrade Controller:"
      puts result
      exit 1
    end

    puts "...k3s System Upgrade Controller deployed."
  end

  private def deploy_cluster_autoscaler
    puts "\nDeploying Cluster Autoscaler..."

    node_pool_args = autoscaling_worker_node_pools.map do |pool|
      autoscaling = pool.autoscaling.not_nil!
      "- --nodes=#{autoscaling.min_instances}:#{autoscaling.max_instances}:#{pool.instance_type.upcase}:#{pool.location.upcase}:#{pool.name}"
    end.join("\n            ")

    k3s_join_script = "|\n    #{worker_install_script.gsub("\n", "\n    ")}"

    cloud_init = Hetzner::Server::Create.cloud_init(settings.ssh_port, settings.snapshot_os, settings.additional_packages, settings.post_create_commands, [k3s_join_script])

    certificate_path = ssh.run(first_master, settings.ssh_port, "[ -f /etc/ssl/certs/ca-certificates.crt ] && echo 1 || echo 2", settings.use_ssh_agent, false).chomp == "1" ? "/etc/ssl/certs/ca-certificates.crt" : "/etc/ssl/certs/ca-bundle.crt"

    cluster_autoscaler_manifest = Crinja.render(CLUSTER_AUTOSCALER_MANIFEST, {
      node_pool_args: node_pool_args,
      cloud_init: Base64.strict_encode(cloud_init),
      image: settings.autoscaling_image || settings.image,
      firewall_name: settings.cluster_name,
      ssh_key_name: settings.cluster_name,
      network_name: (settings.existing_network || settings.cluster_name),
      certificate_path: certificate_path
    })

    cluster_autoscaler_manifest_path = "/tmp/cluster_autoscaler_manifest_path.yaml"

    File.write(cluster_autoscaler_manifest_path, cluster_autoscaler_manifest)

    command = "kubectl apply -f #{cluster_autoscaler_manifest_path}"

    result = Util::Shell.run(command, configuration.kubeconfig_path, settings.hetzner_token)

    unless result.success?
      puts "Failed to deploy Cluster Autoscaler:"
      puts result
      exit 1
    end

    puts "...Cluster Autoscaler deployed."
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

  private def add_labels_or_taints(mark_type, servers, marks, server_type)
    return unless marks.any?

    node_names = servers.map(&.name).join(" ")

    puts "\nAdding #{mark_type}s to #{server_type}s..."

    all_marks = marks.map do |mark|
      "#{mark.key}=#{mark.value}"
    end.join(" ")

    command = "kubectl #{mark_type} --overwrite nodes #{node_names} #{all_marks}"

    Util::Shell.run(command, configuration.kubeconfig_path, settings.hetzner_token)

    puts "...done."
  end

  private def generate_tls_sans
    sans = ["--tls-san=#{api_server_ip_address}"]
    masters.each do |master|
      master_private_ip = master.private_ip_address
      sans << "--tls-san=#{master_private_ip}"
    end
    sans.join(" ")
  end
end
