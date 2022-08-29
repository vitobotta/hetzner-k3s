# frozen_string_literal: true

Net::SSH::Transport::Algorithms::ALGORITHMS.values.each { |algs| algs.reject! { |a| a =~ /^ecd(sa|h)-sha2/ } }
Net::SSH::KnownHosts::SUPPORTED_TYPE.reject! { |t| t =~ /^ecd(sa|h)-sha2/ }

require 'childprocess'

module Utils
  CMD_FILE_PATH = '/tmp/cli.cmd'

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

  def write_file(path, content, append: false)
    File.open(path, append ? 'a' : 'w') { |file| file.write(content) }
  end

  def run(command, kubeconfig_path:)
    write_file CMD_FILE_PATH, <<-CONTENT
    set -euo pipefail
    #{command}
    CONTENT

    FileUtils.chmod('+x', CMD_FILE_PATH)

    begin
      process = ChildProcess.build('bash', '-c', CMD_FILE_PATH)
      process.io.inherit!
      process.environment['KUBECONFIG'] = kubeconfig_path
      process.environment['HCLOUD_TOKEN'] = ENV.fetch('HCLOUD_TOKEN', '')

      at_exit do
        process.stop
      rescue Errno::ESRCH, Interrupt
        # ignore
      end

      process.start
      process.wait
    rescue Interrupt
      puts 'Command interrupted'
      exit 1
    end
  end

  def wait_for_ssh(server)
    retries = 0

    Timeout.timeout(5) do
      server_name = server['name']

      puts "Waiting for server #{server_name} to be up..."

      loop do
        result = ssh(server, 'cat /etc/ready')
        break if result == 'true'
      end

      puts "...server #{server_name} is now up."
    end
  rescue Errno::ENETUNREACH, Errno::EHOSTUNREACH, Timeout::Error, IOError, Errno::ECONNRESET
    retries += 1
    retry if retries <= 15
  end

  def ssh(server, command, print_output: false)
    retries = 0

    public_ip = server.dig('public_net', 'ipv4', 'ip')
    output = ''

    params = { verify_host_key: (verify_host_key ? :always : :never) }

    params[:keys] = private_ssh_key_path && [private_ssh_key_path]

    Net::SSH.start(public_ip, 'root', params) do |session|
      session.exec!(command) do |_channel, _stream, data|
        output = "#{output}#{data}"
        puts data if print_output
      end
    end
    output.chop
  # rescue StandardError => e
  #   p [e.class, e.message]
  #   retries += 1
  #   retry unless retries > 15 || e.message =~ /Bad file descriptor/
  rescue Timeout::Error, IOError, Errno::EBADF
    retries += 1
    retry unless retries > 15
  rescue Net::SSH::Disconnect => e
    retries += 1
    retry unless retries > 15 || e.message =~ /Too many authentication failures/
  rescue Net::SSH::ConnectionTimeout, Errno::ECONNREFUSED, Errno::ENETUNREACH, Errno::EHOSTUNREACH
    retries += 1
    retry if retries <= 15
  rescue Net::SSH::AuthenticationFailed
    puts '\nCannot continue: SSH authentication failed. Please ensure that the private SSH key is correct.'
    exit 1
  rescue Net::SSH::HostKeyMismatch
    puts <<-MESSAGE
    Cannot continue: Unable to SSH into server with IP #{public_ip} because the existing fingerprint in the known_hosts file does not match that of the actual host key.\n
    This is due to a security check but can also happen when creating a new server that gets assigned the same IP address as another server you've owned in the past.\n
    If are sure no security is being violated here and you're just creating new servers, you can eiher remove the relevant lines from your known_hosts (see IPs from the cloud console) or disable host key verification by setting the option 'verify_host_key' to false in the configuration file for the cluster.
    MESSAGE
    exit 1
  end
end
