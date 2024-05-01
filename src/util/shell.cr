require "./shell/command_result"
require "random/secure"

module Util
  module Shell
    def run_shell_command(command : String, kubeconfig_path : String, hetzner_token : String, error_message : String = "", abort_on_error  = true, log_prefix = "", print_output : Bool = true) : CommandResult
      cmd_file_path = "/tmp/cli_#{Random::Secure.hex(8)}.cmd"

      File.write(cmd_file_path, <<-CONTENT
      set -euo pipefail
      #{command}
      CONTENT
      )

      File.chmod(cmd_file_path, 0o700)

      stdout = IO::Memory.new
      stderr = IO::Memory.new

      log_prefix = log_prefix.blank? ? default_log_prefix : log_prefix

      if print_output
        all_io_out = if log_prefix.blank?
          IO::MultiWriter.new(STDOUT, stdout)
        else
          IO::MultiWriter.new(PrefixedIO.new("[#{log_prefix}] ", STDOUT), stdout)
        end

        all_io_err = IO::MultiWriter.new(STDERR, stderr)
      else
        all_io_out = stdout
        all_io_err = stderr
      end

      env = {
        "KUBECONFIG" => kubeconfig_path,
        "HCLOUD_TOKEN" => hetzner_token
      }

      status = Process.run("bash",
        args: ["-c", cmd_file_path],
        env: env,
        output: all_io_out,
        error: all_io_err
      )

      output = status.success? ? stdout.to_s : stderr.to_s
      result = CommandResult.new(output, status.exit_code)

      unless result.success?
        log_line "#{error_message}: #{result.output}", log_prefix: log_prefix if print_output
        exit 1 if abort_on_error
      end

      result
    end
  end
end
