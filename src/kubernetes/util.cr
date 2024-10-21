require "../util"
require "../util/shell"
require "socket"

module Kubernetes::Util
  include ::Util
  include ::Util::Shell

  def ensure_kubectl_is_installed!
    return if which("kubectl")

    log_line "Please ensure kubectl is installed and in your PATH.", log_prefix: "Tooling"
    exit 1
  end

  def apply_manifest_from_yaml(yaml)
    command = <<-BASH
    kubectl apply -f  - <<-EOF
    #{yaml}
    EOF
    BASH

    result = run_shell_command(command, configuration.kubeconfig_path, settings.hetzner_token)

    unless result.success?
      log_line "Failed to apply manifest: #{result.output}"
      exit 1
    end
  end

  def apply_manifest_from_url(url)
    command = "kubectl apply -f #{url}"

    result = run_shell_command(command, configuration.kubeconfig_path, settings.hetzner_token)

    unless result.success?
      log_line "Failed to apply manifest: #{result.output}"
      exit 1
    end
  end

  def apply_kubectl_command(command, error_message = "")
    result = run_shell_command(command, configuration.kubeconfig_path, settings.hetzner_token)

    unless result.success?
      log_line "#{error_message}: #{result.output}"
      exit 1
    end
  end

  def fetch_manifest(url)
    response = Crest.get(url)

    unless response.success?
      log_line "Failed to fetch manifest from #{url}: Server responded with status #{response.status_code}"
      exit 1
    end

    response.body.to_s
  end

  def kubernetes_component_args_list(settings_group, setting)
    setting.map { |arg| " --#{settings_group}-arg \"#{arg}\" " }.join
  end

  def port_open?(ip, port, timeout = 1.0)
    begin
      socket = TCPSocket.new(ip, port, connect_timeout: timeout)
      socket.close
      true
    rescue Socket::Error | IO::TimeoutError
      false
    end
  end

  def api_server_ready?(kubeconfig_path)
    return false unless File.exists?(kubeconfig_path)

    kubeconfig = YAML.parse(File.read(kubeconfig_path))
    server = kubeconfig["clusters"][0]["cluster"]["server"].as_s
    ip_address = server.split(":")[1].gsub("//", "")
    port = server.split(":")[2]

    port_open?(ip_address, port, timeout = 1.0)
  end

  private def present?(value : String?)
    value.try(&.strip).try(&.empty?) == false
  end
end
