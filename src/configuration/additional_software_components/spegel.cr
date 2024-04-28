class Configuration::AdditionalSoftwareComponents::Spegel
  include YAML::Serializable
  include YAML::Serializable::Unmapped

  getter enabled : Bool = true
  getter chart_version : String = "v0.0.22"

  def initialize
  end
end
