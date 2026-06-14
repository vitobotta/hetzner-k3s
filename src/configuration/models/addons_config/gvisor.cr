module Configuration
  module Models
    module AddonsConfig
      class GVisor
        include YAML::Serializable
        include YAML::Serializable::Unmapped

        # Whether to enable gVisor (runsc) as an additional container runtime
        property enabled : Bool = false

        def initialize(@enabled : Bool = false)
        end

        def enabled?
          enabled
        end
      end
    end
  end
end
