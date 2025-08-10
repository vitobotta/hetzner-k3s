require "./kubectl_presence"

class Configuration::Validators::RunSettings
  getter errors : Array(String) = [] of String

  def initialize(@errors)
  end

  def validate
    Configuration::Validators::KubectlPresence.new(errors).validate
  end
end
