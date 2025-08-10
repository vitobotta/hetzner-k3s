require "../../util"

class Configuration::Validators::HelmPresence
  getter errors : Array(String) = [] of String

  def initialize(@errors)
  end

  def validate
    errors << "helm is not installed or not in PATH" unless Util.which("helm")
  end
end