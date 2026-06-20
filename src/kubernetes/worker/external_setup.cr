require "base64"

require "../../configuration/loader"
require "../../configuration/main"
require "../../hetzner/instance"
require "../../util/ssh"
require "../deployment_helper"
require "../local_firewall/setup"
require "../script/worker_generator"
require "../script/labels_and_taints_generator"

class Kubernetes::Worker::ExternalSetup
  include Kubernetes::DeploymentHelper

  getter settings : Configuration::Main
  getter ssh : ::Util::SSH

  private getter local_firewall_setup : Kubernetes::LocalFirewall::Setup
  private getter worker_generator : Kubernetes::Script::WorkerGenerator

  def initialize(
    @configuration : Configuration::Loader,
    @settings : Configuration::Main,
    @ssh : ::Util::SSH,
    @worker_generator : Kubernetes::Script::WorkerGenerator
  )
    @local_firewall_setup = Kubernetes::LocalFirewall::Setup.new(settings, ssh)
  end

  def set_up_external_workers(masters : Array(Hetzner::Instance), first_master : Hetzner::Instance) : Nil
    external_pools = settings.worker_node_pools.select(&.external?)
    return if external_pools.empty?

    external_pools.each do |pool|
      pool.external.not_nil!.nodes.each do |node|
        set_up_external_worker(node, pool, masters, first_master)
      end
    end
  end

  private def set_up_external_worker(node, pool, masters, first_master)
    node_ssh = Util::SSH.new(node.ssh_private_key_path, "", false, node.ssh_user)
    instance = Hetzner::Instance.new(0, "running", node.host, node.host, node.host)
    use_sudo = node.ssh_user != "root"

    log_line "Setting up external node #{node.host}...", node.host

    # a. Hostname management
    if node.manage_hostname
      hostname = build_external_hostname(pool, node.index)
      run_ssh(node_ssh, instance, node.ssh_port, sudo_command("hostnamectl set-hostname #{hostname}", use_sudo))
    end

    # d. Package installation
    install_packages(node_ssh, instance, node.ssh_port, pool, use_sudo)

    # DNS resolver (same as cloud-init)
    run_ssh(node_ssh, instance, node.ssh_port, sudo_command("echo nameserver 8.8.8.8 > /etc/k8s-resolv.conf", use_sudo))

    deploy_firewall(instance, node_ssh, node.ssh_port, use_sudo)

    # e. Pre-k3s commands
    run_pre_k3s_commands(node_ssh, instance, node.ssh_port, pool, use_sudo)

    # f. k3s installation — generate and deploy worker install script
    script = generate_worker_script(masters, first_master, pool)
    if use_sudo
      # The worker install script writes to /etc, runs the k3s installer, etc.
      # Pipe it to sudo bash so it runs as root.
      run_ssh(node_ssh, instance, node.ssh_port, "echo '#{Base64.strict_encode(script)}' | base64 -d | sudo bash")
    else
      run_ssh(node_ssh, instance, node.ssh_port, script)
    end

    # g. Post-k3s commands
    run_post_k3s_commands(node_ssh, instance, node.ssh_port, pool, use_sudo)

    log_line "...external node #{node.host} set up", node.host
  end

  private def build_external_hostname(pool, index) : String
    include_type = settings.include_instance_type_in_instance_name
    instance_type_part = include_type ? "#{pool.instance_type}-" : ""
    "#{settings.cluster_name}-#{instance_type_part}pool-#{pool.name}-worker#{index}"
  end

  private def install_packages(ssh, instance, port, pool, use_sudo)
    packages = ["fail2ban", "wireguard"] + (pool.additional_packages || [] of String)
    packages_str = packages.join(" ")
    run_ssh(ssh, instance, port, sudo_command("export DEBIAN_FRONTEND=noninteractive && apt-get update -qq && apt-get install -y -qq #{packages_str}", use_sudo))
  end

  private def deploy_firewall(instance, ssh, port, use_sudo)
    @local_firewall_setup.deploy_with_ssh(instance, ssh, port, use_sudo)
  end

  private def run_pre_k3s_commands(ssh, instance, port, pool, use_sudo)
    commands = pool.additional_pre_k3s_commands || [] of String
    return if commands.empty?
    commands.each do |cmd|
      run_ssh(ssh, instance, port, sudo_command(cmd, use_sudo))
    end
  end

  private def run_post_k3s_commands(ssh, instance, port, pool, use_sudo)
    commands = pool.additional_post_k3s_commands || [] of String
    return if commands.empty?
    commands.each do |cmd|
      run_ssh(ssh, instance, port, sudo_command(cmd, use_sudo))
    end
  end

  # Wrap a command so it runs as root when use_sudo is true.
  # Uses base64 encoding + sudo bash to handle redirections, pipes, &&, etc.
  private def sudo_command(command : String, use_sudo : Bool) : String
    if use_sudo
      "echo '#{Base64.strict_encode(command)}' | base64 -d | sudo bash"
    else
      command
    end
  end

  private def generate_worker_script(masters, first_master, pool) : String
    @worker_generator.generate_script(masters, first_master, pool)
  end

  private def run_ssh(ssh, instance, port, script)
    ssh.run(instance, port, script, false)
  end

  private def log_line(message, node_name = nil)
    prefix = node_name ? "External Worker Setup - #{node_name}" : "External Worker Setup"
    puts "[#{prefix}] #{message}"
  end
end
