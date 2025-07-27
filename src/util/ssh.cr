require "io"
require "../util"
require "retriable"
require "tasker"
require "./prefixed_io"
require "./shell"

class Util::SSH
  include ::Util
  include ::Util::Shell

  # Default SSH connection timeout in seconds
  DEFAULT_CONNECT_TIMEOUT = 15
  # Default SSH command timeout in seconds
  DEFAULT_COMMAND_TIMEOUT = 30
  # Default number of retry attempts
  DEFAULT_MAX_ATTEMPTS = 20
  # Default delay between retries in seconds
  DEFAULT_RETRY_DELAY = 5

  getter private_ssh_key_path : String
  getter public_ssh_key_path : String

  def initialize(@private_ssh_key_path, @public_ssh_key_path)
  end

  # Wait for an instance to be ready by repeatedly running a test command until it returns the expected result
  def wait_for_instance(
    instance,
    port,
    use_ssh_agent,
    test_command,
    expected_result,
    max_attempts : Int32 = DEFAULT_MAX_ATTEMPTS,
    retry_delay : Time::Span = DEFAULT_RETRY_DELAY.seconds
  )
    result_str = ""
    debug = ENV.fetch("DEBUG", "false") == "true"

    Retriable.retry(
      max_attempts: max_attempts,
      on: [Tasker::Timeout, IO::Error],
      backoff: false,
      sleep_timer: retry_delay
    ) do
      result = nil
      begin
        Tasker.timeout(DEFAULT_COMMAND_TIMEOUT.seconds) do
          result = run(instance, port, test_command, use_ssh_agent, false)
        end

        result_str = result.to_s.strip.gsub(/[\r\n]+/, "\n")

        if debug
          puts "SSH command result: ===#{result_str}==="
          puts "SSH command expected: ===#{expected_result}==="
          puts "Matching?: ===#{result_str == expected_result}==="
        end

        unless result_str == expected_result
          log_line "Instance #{instance.name} not ready, retrying...", log_prefix: "Instance #{instance.name}"
          raise IO::Error.new("Result mismatch")
        end
      rescue ex : Tasker::Timeout
        log_line "SSH command timed out for instance #{instance.name}",
                 log_prefix: "Instance #{instance.name}"
        raise ex
      rescue ex
        log_line "SSH connection failed for instance #{instance.name}: #{ex.message}",
                 log_prefix: "Instance #{instance.name}"
        raise ex
      end
    end

    log_line "Instance #{instance.name} is ready", log_prefix: "Instance #{instance.name}" if debug
    result_str
  end

  # Run a command on a remote instance via SSH
  def run(instance, port, command, use_ssh_agent, print_output = true)
    host_ip_address = instance.host_ip_address
    raise "Instance #{instance.name} has no IP address" unless host_ip_address

    debug = ENV.fetch("DEBUG", "false") == "true"
    log_level = debug ? "DEBUG" : "ERROR"

    ssh_args = build_ssh_args(
      host_ip_address: host_ip_address,
      port: port,
      command: command,
      use_ssh_agent: use_ssh_agent,
      log_level: log_level
    )

    stdout = IO::Memory.new
    stderr = IO::Memory.new

    output_streams = setup_output_streams(instance.name, stdout, stderr, print_output, debug)

    status = Process.run("ssh",
      args: ssh_args,
      output: output_streams[:out],
      error: output_streams[:err]
    )

    unless status.success?
      error_msg = stderr.to_s.strip
      log_line "SSH command failed (exit code: #{status.exit_code}): #{error_msg}",
               log_prefix: "Instance #{instance.name}" if debug
      raise IO::Error.new("SSH command failed on #{instance.name}: #{error_msg}")
    end

    stdout.to_s.strip
  end

  private def build_ssh_args(host_ip_address, port, command, use_ssh_agent, log_level)
    args = [
      "-o", "ConnectTimeout=#{DEFAULT_CONNECT_TIMEOUT}",
      "-o", "StrictHostKeyChecking=no",
      "-o", "UserKnownHostsFile=/dev/null",
      "-o", "BatchMode=yes",
      "-o", "LogLevel=#{log_level}",
      "-o", "ServerAliveInterval=10",
      "-o", "ServerAliveCountMax=3",
      "-o", "PasswordAuthentication=no",
      "-o", "PreferredAuthentications=publickey",
      "-o", "PubkeyAuthentication=yes"
    ]

    # Add private key if not using SSH agent
    unless use_ssh_agent
      args.concat(["-i", private_ssh_key_path])
    end

    # Add port, user@host, and command
    args.concat(["-p", port.to_s, "root@#{host_ip_address}", command])

    args
  end

  private def setup_output_streams(instance_name, stdout, stderr, print_output, debug)
    if print_output || debug
      {
        out: IO::MultiWriter.new(PrefixedIO.new("[Instance #{instance_name}] ", STDOUT), stdout),
        err: IO::MultiWriter.new(PrefixedIO.new("[Instance #{instance_name}] ", STDERR), stderr)
      }
    else
      {
        out: stdout,
        err: stderr
      }
    end
  end

  private def default_log_prefix
    "+"
  end
end
