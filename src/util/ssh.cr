require "ssh2"

class Util::SSH
  getter private_ssh_key_path : String
  getter public_ssh_key_path : String

  def initialize(@private_ssh_key_path, @public_ssh_key_path)
  end

  def run(server, command)
    host_ip_address = server.public_ip_address.not_nil!

    SSH2::Session.open(host_ip_address) do |session|
      session.login_with_pubkey("root", private_ssh_key_path, public_ssh_key_path)

      session.open_session do |channel|
        channel.command(command)
        IO.copy(channel, STDOUT)
      end
    end
  end
end
