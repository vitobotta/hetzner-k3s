class Configuration::Validators::HelmPresence
  getter errors : Array(String) = [] of String

  def initialize(@errors)
  end

  def validate
    errors << "helm is not installed or not in PATH" unless which("helm")
  end

  private def which(command)
    exts = ENV.fetch("PATHEXT", "").split(";")
    paths = ENV["PATH"]?.try(&.split(Process::PATH_DELIMITER)) || [] of String

    paths.each do |path|
      exts.each do |ext|
        exe = File.join(path, "#{command}#{ext}")
        return exe if File::Info.executable?(exe) && !File.directory?(exe)
      end
    end

    nil
  end
end