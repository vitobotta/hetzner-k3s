require "base64"

require "../../configuration/loader"
require "../../configuration/main"
require "../../hetzner/instance"
require "../../hetzner/robot/client"
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

  def wait_for_external_workers_to_be_ready(first_master : Hetzner::Instance) : Nil
    expected_count = settings.worker_node_pools.select(&.external?).sum { |pool| pool.external.not_nil!.nodes.size }
    return if expected_count == 0

    log_line "Waiting for #{expected_count} external worker node(s) to be ready...", nil

    timeout = Time.monotonic + 5.minutes

    loop do
      output = ssh.run(first_master, settings.networking.ssh.port, "KUBECONFIG=/etc/rancher/k3s/k3s.yaml kubectl get nodes -l hetzner-k3s.io/external=true -o=custom-columns=NAME:.metadata.name,STATUS:.status.conditions[?(@.type==\"Ready\")].status --no-headers 2>/dev/null", settings.networking.ssh.use_agent, print_output: false)

      ready_count = output.lines.count { |line| line.includes?("True") }

      break if ready_count >= expected_count

      if Time.monotonic > timeout
        log_line "Timeout waiting for external worker nodes to be ready (#{ready_count}/#{expected_count} ready), aborting", nil
        exit 1
      end

      sleep 5.seconds
    end

    log_line "...all external worker nodes are ready", nil
  end

  private def set_up_external_worker(node, pool, masters, first_master)
    node_ssh = Util::SSH.new(node.ssh_private_key_path, "", false, node.ssh_user)
    instance = Hetzner::Instance.new(0, "running", node.host, node.host, node.host)
    use_sudo = node.ssh_user != "root"

    log_line "Setting up external node #{node.host}...", node.host

    # Idempotency: if the node is already initialized, skip the destructive
    # setup steps (hostname, packages, pre/post commands, k3s install) but
    # still reconcile the firewall, which is safe to redeploy.
    if node_initialized?(node_ssh, instance, node.ssh_port, use_sudo)
      log_line "External node #{node.host} is already initialized, reconciling firewall only", node.host
      deploy_firewall(instance, node_ssh, node.ssh_port, use_sudo)
      log_line "...external node #{node.host} set up", node.host
      return
    end

    # a. Hostname management
    if node.manage_hostname
      hostname = settings.external_worker_hostname(pool, node.index)
      sync_robot_hostname(node, pool, hostname) if pool.external.not_nil!.robot?
      run_ssh(node_ssh, instance, node.ssh_port, sudo_command("hostnamectl set-hostname #{hostname}", use_sudo))
    end

    # d. Package installation
    install_packages(node_ssh, instance, node.ssh_port, pool, use_sudo)

    # DNS resolver (same as cloud-init)
    run_ssh(node_ssh, instance, node.ssh_port, sudo_command("echo nameserver 8.8.8.8 > /etc/k8s-resolv.conf", use_sudo))

    deploy_firewall(instance, node_ssh, node.ssh_port, use_sudo)

    # e. Pre-k3s commands
    run_pre_k3s_commands(node_ssh, instance, node.ssh_port, pool, use_sudo)

    # f. k3s installation — generate and deploy worker install script.
    # Base64-encode and pipe to bash (via sudo when the SSH user is not root)
    # so the script content is transmitted verbatim without shell interpretation.
    script = generate_worker_script(masters, first_master, pool, node)
    runner = use_sudo ? "sudo bash" : "bash"
    run_ssh(node_ssh, instance, node.ssh_port, "echo '#{Base64.strict_encode(script)}' | base64 -d | #{runner}")

    # g. Post-k3s commands
    run_post_k3s_commands(node_ssh, instance, node.ssh_port, pool, use_sudo)

    log_line "...external node #{node.host} set up", node.host
  end

  private def node_initialized?(ssh, instance, port, use_sudo) : Bool
    check = sudo_command("test -f /etc/initialized && echo yes || echo no", use_sudo)
    output = ssh.run(instance, port, check, false, print_output: false).strip
    output == "yes"
  rescue
    false
  end

  private def sync_robot_hostname(node, pool, hostname) : Nil
    robot_server_number = node.robot_server_number
    return unless robot_server_number

    external_config = pool.external.not_nil!
    robot_client = Hetzner::Robot::Client.new(external_config.robot_user, external_config.robot_password)
    robot_server = robot_client.server(robot_server_number)
    return if robot_server.name == hostname

    log_line "Updating Robot server #{robot_server_number} name to #{hostname}...", node.host
    robot_client.update_server_name(robot_server_number, hostname)
  rescue ex : Hetzner::Robot::Client::Error
    log_line "Failed to update Robot server #{node.robot_server_number} name: #{ex.message}", node.host
    exit 1
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

  private def generate_worker_script(masters, first_master, pool, node) : String
    @worker_generator.generate_script(masters, first_master, pool, node)
  end

  private def run_ssh(ssh, instance, port, script)
    ssh.run(instance, port, script, false)
  end

  private def log_line(message, node_name = nil)
    prefix = node_name ? "External Worker Setup - #{node_name}" : "External Worker Setup"
    puts "[#{prefix}] #{message}"
  end
end
