module Configuration
  class Timeouts
    include YAML::Serializable
    include YAML::Serializable::Unmapped

    getter instance_creation_timeout : Int64 = 60

    def initialize
    end
  end
end

