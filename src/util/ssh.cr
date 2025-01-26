require "io"
require "../util"
require "retriable"
require "tasker"
require "./prefixed_io"
require "./shell"

class Util::SSH
  include ::Util
  include ::Util::Shell

  getter private_ssh_key_path : String
  getter public_ssh_key_path : String

  def initialize(@private_ssh_key_path, @public_ssh_key_path)
  end

  def wait_for_instance(instance, port, use_ssh_agent, test_command, expected_result, max_attempts : Int16 = 20)
    result = nil

    loop do
      sleep 5.seconds

      Retriable.retry(max_attempts: max_attempts, on: Tasker::Timeout, backoff: false) do
        Tasker.timeout(5.second) do
          result = run(instance, port, test_command, use_ssh_agent, false)
        end
      end

      break result if result == expected_result
    end

    result
  end

  def run(instance, port, command, use_ssh_agent, print_output = true)
    host_ip_address = instance.host_ip_address.not_nil!

    cmd_file_path = "/tmp/cli_#{Random::Secure.hex(8)}.cmd"

    File.write(cmd_file_path, <<-CONTENT
    set -euo pipefail
    #{command}
    CONTENT
    )

    debug_args = if ENV.fetch("DEBUG", "false") == "true"
      " 2>&1 "
    else
      " 2>/dev/null "
    end

    File.chmod(cmd_file_path, 0o700)

    ssh_args = "-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -o ConnectTimeout=5 -o ServerAliveInterval=5 -o ServerAliveCountMax=3 -o BatchMode=yes -o PasswordAuthentication=no -o PreferredAuthentications=publickey -o PubkeyAuthentication=yes -o IdentitiesOnly=yes -i #{private_ssh_key_path}"

    result = run_shell_command("scp #{ssh_args} -P #{port} #{cmd_file_path} root@#{host_ip_address}:#{cmd_file_path}", "", "", "", false, "Instance #{instance.name}", print_output)

    ssh_command = "ssh #{ssh_args} -p #{port} root@#{host_ip_address}"

    result = run_shell_command("#{ssh_command} #{cmd_file_path} #{debug_args}", "", "", "", false, "Instance #{instance.name}", print_output)
    run_shell_command("#{ssh_command} rm #{cmd_file_path}", "", "", "", false, "Instance #{instance.name}", print_output)

    File.delete(cmd_file_path)

    result.output.chomp
  end

  private def default_log_prefix
    "+"
  end
end
