require "../util"
require "../util/shell"
require "socket"

module Kubernetes::Util
  include ::Util
  include ::Util::Shell

  def ensure_kubectl_is_installed! : Nil
    return if which("kubectl")

    log_line "Please ensure kubectl is installed and in your PATH.", log_prefix: "Tooling"
    exit 1
  end

  private def execute_kubectl_command(command : String, error_message : String) : Util::Shell::CommandResult
    result = run_shell_command(command, configuration.kubeconfig_path, settings.hetzner_token)

    unless result.success?
      log_line "#{error_message}: #{result.output}"
      exit 1
    end

    result
  end

  def apply_manifest_from_yaml(yaml : String, error_message = "Failed to apply manifest") : Util::Shell::CommandResult
    command = <<-BASH
    kubectl apply -f  - <<-EOF
    #{yaml}
    EOF
    BASH

    execute_kubectl_command(command, error_message)
  end

  def apply_manifest_server_side(yaml : String, error_message = "Failed to apply manifest") : Util::Shell::CommandResult
    command = <<-BASH
    kubectl apply --server-side --force-conflicts -f - <<-'EOF'
    #{yaml}
    EOF
    BASH

    execute_kubectl_command(command, error_message)
  end

  def apply_manifest_from_url(url : String, error_message = "Failed to apply manifest") : Util::Shell::CommandResult
    command = "kubectl apply -f #{url}"
    execute_kubectl_command(command, error_message)
  end

  def apply_kubectl_command(command : String, error_message = "") : Util::Shell::CommandResult
    execute_kubectl_command(command, error_message)
  end

  def fetch_manifest(url : String) : String
    response = Crest.get(url)

    unless response.success?
      log_line "Failed to fetch manifest from #{url}: Server responded with status #{response.status_code}"
      exit 1
    end

    response.body.to_s
  end

  def self.kubernetes_component_args_list(settings_group : String, setting : Array(String)) : String
    setting.map { |arg| " --#{settings_group}-arg \"#{arg}\" " }.join
  end

  def kubernetes_component_args_list(settings_group : String, setting : Array(String)) : String
    ::Kubernetes::Util.kubernetes_component_args_list(settings_group, setting)
  end

  def port_open?(ip : String, port : String | Int32, timeout : Float64 = 1.0) : Bool
    socket = nil
    begin
      socket = TCPSocket.new(ip, port.to_s, connect_timeout: timeout)
      true
    rescue Socket::Error | IO::TimeoutError
      false
    ensure
      socket.try(&.close)
    end
  end

  def api_server_ready?(kubeconfig_path : String) : Bool
    return false unless File.exists?(kubeconfig_path)

    begin
      kubeconfig = YAML.parse(File.read(kubeconfig_path))
      server = kubeconfig.dig("clusters", 0, "cluster", "server").try(&.as_s)
      return false unless server

      uri = URI.parse(server)
      host = uri.host
      port = uri.port
      return false unless host && port

      port_open?(host, port)
    rescue ex
      log_line "Error checking API server readiness: #{ex.message}"
      false
    end
  end

  def switch_to_context(context : String, abort_on_error = true, request_timeout : Int32? = nil, print_output = true) : Util::Shell::CommandResult
    base = "KUBECONFIG=#{configuration.kubeconfig_path} kubectl config use-context #{context}"
    command_parts = [base]
    command_parts << "--request-timeout=#{request_timeout}s" if request_timeout
    command_parts << "2>/dev/null" unless print_output

    command = command_parts.join(" ")
    run_shell_command(command, "", settings.hetzner_token,
      log_prefix: "Control plane",
      abort_on_error: abort_on_error,
      print_output: print_output)
  end
end
