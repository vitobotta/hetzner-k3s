require "../../util"

class Configuration::Validators::KubectlPresence
  getter errors : Array(String) = [] of String

  def initialize(@errors)
  end

  def validate
    errors << "kubectl is not installed or not in PATH" unless Util.which("kubectl")
  end
end