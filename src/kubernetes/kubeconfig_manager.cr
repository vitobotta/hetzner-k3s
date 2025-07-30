require "file_utils"
require "../util"
require "../util/ssh"
require "../hetzner/instance"
require "../configuration/loader"

class Kubernetes::KubeconfigManager
  include Util

  def initialize(@configuration : Configuration::Loader, @settings : Configuration::Main, @ssh : ::Util::SSH)
  end

  private def default_log_prefix
    "Kubeconfig Manager"
  end

  def save_kubeconfig(masters : Array(Hetzner::Instance), first_master : Hetzner::Instance, load_balancer : Hetzner::LoadBalancer?, use_load_balancer_as_default : Bool = false)
    kubeconfig_path = @configuration.kubeconfig_path

    log_line "Generating the kubeconfig file to #{kubeconfig_path}...", "Control plane"

    kubeconfig = @ssh.run(first_master, @settings.networking.ssh.port, "cat /etc/rancher/k3s/k3s.yaml", @settings.networking.ssh.use_agent, print_output: false)
      .gsub("default", @settings.cluster_name)

    File.write(kubeconfig_path, kubeconfig)

    if @settings.create_load_balancer_for_the_kubernetes_api
      load_balancer_kubeconfig_path = "#{kubeconfig_path}-#{@settings.cluster_name}"
      load_balancer_kubeconfig = kubeconfig.gsub("server: https://127.0.0.1:6443", "server: https://#{load_balancer_ip_address(load_balancer)}:6443")

      File.write(load_balancer_kubeconfig_path, load_balancer_kubeconfig)
    end

    masters.each_with_index do |master, index|
      master_ip_address = @settings.networking.public_network.ipv4 ? master.public_ip_address : master.private_ip_address
      master_kubeconfig_path = "#{kubeconfig_path}-#{master.name}"
      master_kubeconfig = kubeconfig
        .gsub("server: https://127.0.0.1:6443", "server: https://#{master_ip_address}:6443")
        .gsub("name: #{@settings.cluster_name}", "name: #{master.name}")
        .gsub("cluster: #{@settings.cluster_name}", "cluster: #{master.name}")
        .gsub("user: #{@settings.cluster_name}", "user: #{master.name}")
        .gsub("current-context: #{@settings.cluster_name}", "current-context: #{master.name}")

      File.write(master_kubeconfig_path, master_kubeconfig)
    end

    paths = @settings.create_load_balancer_for_the_kubernetes_api ? [load_balancer_kubeconfig_path] : [] of String

    paths = (paths + masters.map { |master| "#{kubeconfig_path}-#{master.name}" }).join(":")

    run_shell_command("KUBECONFIG=#{paths} kubectl config view --flatten > #{kubeconfig_path}", "", @settings.hetzner_token, log_prefix: "Control plane")

    default_context = use_load_balancer_as_default && @settings.create_load_balancer_for_the_kubernetes_api ? @settings.cluster_name : first_master.name
    switch_to_context(default_context, kubeconfig_path)

    masters.each do |master|
      FileUtils.rm("#{kubeconfig_path}-#{master.name}")
    end

    File.chmod kubeconfig_path, 0o600

    log_line "...kubeconfig file generated as #{kubeconfig_path}.", "Control plane"
  end

  def generate_tls_sans(masters : Array(Hetzner::Instance), first_master : Hetzner::Instance, load_balancer : Hetzner::LoadBalancer?)
    sans = ["--tls-san=#{api_server_ip_address(first_master)}", "--tls-san=127.0.0.1"]
    sans << "--tls-san=#{load_balancer_ip_address(load_balancer)}" if @settings.create_load_balancer_for_the_kubernetes_api
    sans << "--tls-san=#{@settings.api_server_hostname}" if @settings.api_server_hostname

    masters.each do |master|
      sans << "--tls-san=#{master.private_ip_address}"
      sans << "--tls-san=#{master.public_ip_address}"
    end

    sans.uniq.sort.join(" ")
  end

  private def api_server_ip_address(first_master : Hetzner::Instance)
    first_master.private_ip_address || first_master.public_ip_address
  end

  private def load_balancer_ip_address(load_balancer : Hetzner::LoadBalancer?)
    load_balancer.try(&.public_ip_address)
  end

  private def switch_to_context(context_name : String, kubeconfig_path : String)
    run_shell_command("KUBECONFIG=#{kubeconfig_path} kubectl config use-context #{context_name}", "", @settings.hetzner_token, log_prefix: "Control plane")
  end
end
