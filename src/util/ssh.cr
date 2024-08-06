require "ssh2"
require "io"
require "../util"
require "retriable"
require "tasker"
require "./prefixed_io"

class Util::SSH
  include ::Util

  getter private_ssh_key_path : String
  getter public_ssh_key_path : String

  def initialize(@private_ssh_key_path, @public_ssh_key_path)
  end

  def run(instance, port, command, use_ssh_agent, print_output = true)
    Retriable.retry(max_attempts: 300, backoff: false, base_interval: 1.second, on: {SSH2::SSH2Error, SSH2::SessionError, Socket::ConnectError}) do
      run_command(instance, port, command, use_ssh_agent, print_output)
    end
  end

  def wait_for_instance(instance, port, use_ssh_agent, test_command, expected_result, max_attempts : Int16 = 20)
    result = nil

    loop do
      log_line "Waiting for successful ssh connectivity with instance #{instance.name}...", log_prefix: "Instance #{instance.name}"

      sleep 1

      Retriable.retry(max_attempts: max_attempts, on: Tasker::Timeout, backoff: false) do
        Tasker.timeout(5.second) do
          result = run(instance, port, test_command, use_ssh_agent, false)
          log_line result, log_prefix: "Instance #{instance.name}" if result != expected_result
        end
      end

      break result if result == expected_result
    end

    log_line "...instance #{instance.name} is now up.", log_prefix: "Instance #{instance.name}"

    result
  end

  private def run_command(instance, port, command, use_ssh_agent, print_output = true)
    host_ip_address = instance.host_ip_address.not_nil!

    result = IO::Memory.new
    all_output = if print_output
      IO::MultiWriter.new(PrefixedIO.new("[Instance #{instance.name}] ", STDOUT), result)
    else
      IO::MultiWriter.new(result)
    end

    SSH2::Session.open(host_ip_address, port) do |session|
      session.timeout = 5000
      session.knownhosts.delete_if { |h| h.name == instance.host_ip_address }

      if use_ssh_agent
        session.login_with_agent("root")
      else
        session.login_with_pubkey("root", private_ssh_key_path, public_ssh_key_path)
      end

      session.open_session do |channel|
        channel.command(command)
        IO.copy(channel, all_output)
      end
    end

    result.to_s.chomp
  end

  private def default_log_prefix
    "+"
  end
end
