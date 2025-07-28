require "./shell/command_result"
require "random/secure"
require "file_utils"

module Util
  module Shell
    def run_shell_command(
      command : String,
      kubeconfig_path : String,
      hetzner_token : String,
      error_message : String = "",
      abort_on_error : Bool = true,
      log_prefix : String = "",
      print_output : Bool = true
    ) : CommandResult
      stdout = IO::Memory.new
      stderr = IO::Memory.new

      log_prefix = log_prefix.blank? ? default_log_prefix : log_prefix

      output_streams = setup_output_streams(log_prefix, stdout, stderr, print_output)

      env = {
        "KUBECONFIG" => kubeconfig_path,
        "HCLOUD_TOKEN" => hetzner_token
      }

      # Use a temporary file to avoid argument length limitations
      tmp_file = File.tempname("hetzner_k3s_", ".sh")
      begin
        File.write(tmp_file, command)
        File.chmod(tmp_file, 0o755)

        status = nil
        begin
          status = Process.run("bash",
            args: [tmp_file],
            env: env,
            output: output_streams[:out],
            error: output_streams[:err]
          )
        rescue ex
          log_line "Process execution failed: #{ex.message}", log_prefix: log_prefix
          return CommandResult.new("Process execution failed: #{ex.message}", 1)
        end

        output = status.success? ? stdout.to_s : stderr.to_s
        result = CommandResult.new(output, status.exit_status)

        unless result.success?
          error_msg = error_message.blank? ? "Shell command failed" : error_message
          log_line "#{error_msg}: #{result.output}", log_prefix: log_prefix
          exit 1 if abort_on_error
        end

        result
      ensure
        cleanup_temp_file(tmp_file)
      end
    end

    private def setup_output_streams(log_prefix, stdout, stderr, print_output)
      if print_output
        out_stream = log_prefix.blank? ? STDOUT : PrefixedIO.new("[#{log_prefix}] ", STDOUT)
        err_stream = log_prefix.blank? ? STDERR : PrefixedIO.new("[#{log_prefix}] ", STDERR)

        {
          out: IO::MultiWriter.new(out_stream, stdout),
          err: IO::MultiWriter.new(err_stream, stderr)
        }
      else
        {
          out: stdout,
          err: stderr
        }
      end
    end

    private def cleanup_temp_file(tmp_file)
      return unless File.exists?(tmp_file)

      begin
        File.delete(tmp_file)
      rescue ex
        # Log but don't fail if we can't delete the temp file
        # This can happen on some systems or if the file is locked
        log_line "Warning: Could not delete temporary file #{tmp_file}: #{ex.message}",
                 log_prefix: "Shell"
      end
    end
  end
end
