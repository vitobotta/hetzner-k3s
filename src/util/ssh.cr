require "ssh2"
require "io"
require "../util"
require "retriable"
require "tasker"

class Util::SSH
  getter private_ssh_key_path : String
  getter public_ssh_key_path : String

  def initialize(@private_ssh_key_path, @public_ssh_key_path)
  end

  def run(server, port, command, use_ssh_agent, print_output = true)
    Retriable.retry(max_attempts: 300, backoff: false, base_interval: 1.second, on: {SSH2::SSH2Error, SSH2::SessionError, Socket::ConnectError}) do
      run_command(server, port, command, use_ssh_agent, print_output)
    end
  end

  def wait_for_server(server, port, use_ssh_agent, test_command, expected_result)
    puts "Waiting for successful ssh connectivity with server #{server.name}..."

    loop do
      sleep 1

      result = nil

      Retriable.retry(on: Tasker::Timeout, backoff: false) do
        Tasker.timeout(5.seconds) do
          result = run(server, port, test_command, use_ssh_agent, false)
        end
      end

      break if result == expected_result
    end

    puts "...server #{server.name} is now up."
  end

  private def run_command(server, port, command, use_ssh_agent, print_output = true)
    host_ip_address = server.host_ip_address.not_nil!

    result = IO::Memory.new
    all_output = if print_output
      IO::MultiWriter.new(STDOUT, result)
    else
      IO::MultiWriter.new(result)
    end

    SSH2::Session.open(host_ip_address, port) do |session|
      session.timeout = 5000
      session.knownhosts.delete_if { |h| h.name == server.host_ip_address }

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
end
