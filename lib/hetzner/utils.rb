module Utils
  def which(cmd)
    exts = ENV['PATHEXT'] ? ENV['PATHEXT'].split(';') : ['']
    ENV['PATH'].split(File::PATH_SEPARATOR).each do |path|
      exts.each do |ext|
        exe = File.join(path, "#{cmd}#{ext}")
        return exe if File.executable?(exe) && !File.directory?(exe)
      end
    end
    nil
  end

  def run(command, kubeconfig_path:)
    env = ENV.to_hash.merge({
      "KUBECONFIG" => kubeconfig_path
    })

    cmd_path = "/tmp/cli.cmd"

    File.open(cmd_path, "w") do |f|
      f.write("set -euo pipefail\n")
      f.write(command)
    end

    FileUtils.chmod("+x", cmd_path)

    begin
      process = nil

      at_exit do
        begin
          process&.send_signal("SIGTERM")
        rescue Errno::ESRCH, Interrupt
        end
      end

      Subprocess.check_call(["bash", "-c", cmd_path], env: env) do |p|
        process = p
      end

    rescue Subprocess::NonZeroExit
      puts "Command failed: non-zero exit code"
      exit 1
    rescue Interrupt
      puts "Command interrupted"
      exit 1
    end
  end

  def wait_for_ssh(server)
    Timeout::timeout(5) do
      server_name = server["name"]

      puts "Waiting for server #{server_name} to be up..."

      loop do
        result = ssh(server, "echo UP")
        break if result == "UP"
      end

      puts "...server #{server_name} is now up."
    end
  rescue Errno::ENETUNREACH, Errno::EHOSTUNREACH, Timeout::Error, IOError
    retry
  end

  def ssh(server, command, print_output: false)
    public_ip = server.dig("public_net", "ipv4", "ip")
    output = ""

    params = { verify_host_key: (verify_host_key ? :always : :never) }

    if private_ssh_key_path
      params[:keys] = [private_ssh_key_path]
    end

    Net::SSH.start(public_ip, "root", params) do |session|
      session.exec!(command) do |channel, stream, data|
        output << data
        puts data if print_output
      end
    end
    output.chop
  rescue Net::SSH::Disconnect => e
    retry unless e.message =~ /Too many authentication failures/
  rescue Net::SSH::ConnectionTimeout, Errno::ECONNREFUSED, Errno::ENETUNREACH, Errno::EHOSTUNREACH
    retry
  rescue Net::SSH::AuthenticationFailed
    puts
    puts "Cannot continue: SSH authentication failed. Please ensure that the private SSH key is correct."
    exit 1
  rescue Net::SSH::HostKeyMismatch
    puts
    puts "Cannot continue: Unable to SSH into server with IP #{public_ip} because the existing fingerprint in the known_hosts file does not match that of the actual host key."
    puts "This is due to a security check but can also happen when creating a new server that gets assigned the same IP address as another server you've owned in the past."
    puts "If are sure no security is being violated here and you're just creating new servers, you can eiher remove the relevant lines from your known_hosts (see IPs from the cloud console) or disable host key verification by setting the option 'verify_host_key' to false in the configuration file for the cluster."
    exit 1
  end
end
