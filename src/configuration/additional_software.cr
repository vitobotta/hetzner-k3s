require "./additional_software_components/spegel"

module Configuration
  class AdditionalSoftware
    include YAML::Serializable
    include YAML::Serializable::Unmapped

    getter spegel : Configuration::AdditionalSoftwareComponents::Spegel = Configuration::AdditionalSoftwareComponents::Spegel.new

    def initialize
    end
  end
end

