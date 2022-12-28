require "ssh2"
require "io"
require "../util"
require "retriable"

class Util::SSH
  getter private_ssh_key_path : String
  getter public_ssh_key_path : String

  def initialize(@private_ssh_key_path, @public_ssh_key_path)
  end

  def run(server, command, print_output = false)
    host_ip_address = server.public_ip_address.not_nil!

    result = IO::Memory.new

    SSH2::Session.open(host_ip_address) do |session|
      session.login_with_pubkey("root", private_ssh_key_path, public_ssh_key_path)

      session.open_session do |channel|
        channel.command(command)
        IO.copy(channel, STDOUT) if print_output
        IO.copy(channel, result)
      end
    end

    result.to_s.chomp
  end

  def wait_for_server(server)
    puts "Waiting for server #{server.name} to be ready..."

    loop do
      sleep 1

      result = nil

      Retriable.retry(max_attempts: 30, on: {SSH2::SSH2Error, SSH2::SessionError, Socket::ConnectError}) do
        result = run(server, "cat /etc/ready")
      end

      break if result == "true"
    end

    puts "...server #{server.name} is now up."
  end
end
