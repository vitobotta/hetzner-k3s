require "./shell/command_result"
require "random/secure"
require "file_utils"

module Util
  module Shell
    def run_shell_command(command : String, kubeconfig_path : String, hetzner_token : String, error_message : String = "", abort_on_error  = true, log_prefix = "", print_output : Bool = true) : CommandResult
      stdout = IO::Memory.new
      stderr = IO::Memory.new

      log_prefix = log_prefix.blank? ? default_log_prefix : log_prefix

      if print_output
        all_io_out = if log_prefix.blank?
          IO::MultiWriter.new(STDOUT, stdout)
        else
          IO::MultiWriter.new(PrefixedIO.new("[#{log_prefix}] ", STDOUT), stdout)
        end

        all_io_err = if log_prefix.blank?
          IO::MultiWriter.new(STDERR, stderr)
        else
          IO::MultiWriter.new(PrefixedIO.new("[#{log_prefix}] ", STDERR), stderr)
        end
      else
        all_io_out = stdout
        all_io_err = stderr
      end

      env = {
        "KUBECONFIG" => kubeconfig_path,
        "HCLOUD_TOKEN" => hetzner_token
      }

      # Always use a temporary file to avoid argument length limitations
      tmp_file = File.tempname("hetzner_k3s_", ".sh")
      begin
        File.write(tmp_file, command)
        File.chmod(tmp_file, 0o755)

        status = Process.run("bash",
          args: [tmp_file],
          env: env,
          output: all_io_out,
          error: all_io_err
        )
      ensure
        # Clean up the temporary file
        FileUtils.rm_r(tmp_file) if File.exists?(tmp_file)
      end

      output = status.success? ? stdout.to_s : stderr.to_s
      result = CommandResult.new(output, status.exit_status)

      unless result.success?
        log_line "#{error_message}: #{result.output}", log_prefix: log_prefix
        exit 1 if abort_on_error
      end

      result
    end
  end
end
