 module Util
  def self.which(command)
    exts = ENV.fetch("PATHEXT", "").split(";")
    ENV["PATH"].split(Process::PATH_DELIMITER).each do |path|
      exts.each do |ext|
        exe = File.join(path, "#{command}#{ext}")
        return exe if File.executable?(exe) && !File.directory?(exe)
      end
    end
    nil
  end

  def self.check_kubectl
    return if which("kubectl")

    puts "Please ensure kubectl is installed and in your PATH."
    exit 1
  end
end
