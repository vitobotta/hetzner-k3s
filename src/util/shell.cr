module Util
  module Shell
    class Result
      getter output : String
      getter status : Int32

      def initialize(@output, @status)
      end

      def success?
        status.zero?
      end
    end

    def self.run(command : String, kubeconfig_path : String, hetzner_token : String) : Result
      cmd_file_path = "/tmp/cli.cmd"

      File.write(cmd_file_path, <<-CONTENT
      set -euo pipefail
      #{command}
      CONTENT
      )

      File.chmod(cmd_file_path, 0o700)

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

      output = status.success? ? stdout.to_s : stderr.to_s
      Result.new(output, status.exit_code)
    end
  end

  private def self.write_file(path : String, content : String, append : Bool = false)
    mode = append ? "a" : "w"
    File.open(path, mode) do |file|
      file.print(content)
    end
  end
end
