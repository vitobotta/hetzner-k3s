class Util::Shell
  def self.run(command, kubeconfig_path, hetzner_token)
    cmd_file_path = "/tmp/cli.cmd"

    write_file cmd_file_path, <<-CONTENT
    set -euo pipefail
    #{command}
    CONTENT

    File.chmod cmd_file_path, 0o700

    stdout = IO::Memory.new
    stderr = IO::Memory.new

    all_io_out = IO::MultiWriter.new(STDOUT, stdout)
    all_io_err = IO::MultiWriter.new(STDERR, stderr)

    env = {
      "KUBECONFIG" => kubeconfig_path,
      "HCLOUD_TOKEN" => hetzner_token
    }

    status = Process.run("bash",
      args: ["-c", cmd_file_path],
      env: env,
      output: all_io_out,
      error: all_io_err
    )

    if status.success?
      {status.exit_code, stdout.to_s}
    else
      {status.exit_code, stderr.to_s}
    end
  end

  private def self.write_file(path, content, append = false)
    File.open(path, append ? "a" : "w") { |file| file.print(content) }
  end
end
