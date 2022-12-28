# frozen_string_literal: true

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


