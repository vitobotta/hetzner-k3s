module Util
  def which(command)
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

  def log_line(line, log_prefix = "")
    log_prefix = log_prefix.blank? ? default_log_prefix : log_prefix
    puts "[#{log_prefix}] #{line}"
  end

  abstract def default_log_prefix
end
