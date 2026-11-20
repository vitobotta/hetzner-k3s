module Configuration
  module Models
    module AddonsConfig
      class GVisor
        include YAML::Serializable
        include YAML::Serializable::Unmapped

        # The runsc build to install. The gVisor apt repository is a single rolling component, so it
        # is pinned here like the other addon versions and bumped on purpose rather than on every
        # create, which would upgrade the runtime on running nodes.
        DEFAULT_VERSION = "20261116.0"

        # Whether to enable gVisor (runsc) as an additional container runtime
        property enabled : Bool = false

        # The runsc package version installed from the gVisor apt repository
        property version : String = DEFAULT_VERSION

        def initialize(@enabled : Bool = false, @version : String = DEFAULT_VERSION)
        end

        def enabled?
          enabled
        end
      end
    end
  end
end
