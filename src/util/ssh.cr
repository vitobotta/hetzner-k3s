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

      result ||= ""
      result = result.not_nil!.strip.gsub(/[\r\n]/, "")

      if ENV.fetch("DEBUG", "false") == "true"
        puts "SSH command result: ===#{result}==="
        puts "SSH command expected: ===#{expected_result}==="
        puts "Matching?: ===#{ result == expected_result }==="
      end

      if result == expected_result
        break result
      else
        log_line "Waiting for instance #{instance.name} to be ready...", log_prefix: "Instance #{instance.name}"
      end
    end

    result
  end

  def run(instance, port, command, use_ssh_agent, print_output = true)
    host_ip_address = instance.host_ip_address.not_nil!
    debug = ENV.fetch("DEBUG", "false") == "true"
    log_level = debug ? "DEBUG" : "ERROR"

    ssh_args = [
      "-o ConnectTimeout=10",
      "-o StrictHostKeyChecking=no",
      "-o UserKnownHostsFile=/dev/null",
      "-o BatchMode=yes",
      "-o LogLevel=#{log_level}",
      "-o ServerAliveInterval=5",
      "-o ServerAliveCountMax=3",
      "-o PasswordAuthentication=no",
      "-o PreferredAuthentications=publickey",
      "-o PubkeyAuthentication=yes",
      "-i", private_ssh_key_path,
      "-p", port.to_s,
      "root@#{host_ip_address}",
      command
    ]

    stdout = IO::Memory.new
    stderr = IO::Memory.new

    if print_output || debug
      all_io_out = IO::MultiWriter.new(PrefixedIO.new("[Instance #{instance.name}] ", STDOUT), stdout)
      all_io_err = IO::MultiWriter.new(PrefixedIO.new("[Instance #{instance.name}] ", STDERR), stderr)
    else
      all_io_out = stdout
      all_io_err = stderr
    end

    status = Process.run("ssh",
      args: ssh_args,
      output: all_io_out,
      error: all_io_err
    )

    unless status.success?
      log_line "SSH command failed: #{stderr.to_s}", log_prefix: "Instance #{instance.name}" if debug
    end

    stdout.to_s.strip.chomp
  end

  private def default_log_prefix
    "+"
  end
end
