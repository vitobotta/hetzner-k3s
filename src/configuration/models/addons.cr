module Configuration
  module Models
    class Addons
      include YAML::Serializable
      include YAML::Serializable::Unmapped

      # Generic toggle struct – can be extended later with more settings per addon
      class Toggle
        include YAML::Serializable
        include YAML::Serializable::Unmapped

        getter enabled : Bool

        def initialize(@enabled : Bool = true)
        end

        def enabled?
          enabled
        end
      end

      # Addon definitions with sensible defaults (true unless specified otherwise)
      getter csi_driver : Toggle = Toggle.new(true)
      getter traefik : Toggle = Toggle.new(false)
      getter servicelb : Toggle = Toggle.new(false)
      getter metrics_server : Toggle = Toggle.new(false)
      getter cloud_controller_manager : Toggle = Toggle.new(true)
      getter cluster_autoscaler : Toggle = Toggle.new(true)

      def initialize
      end
    end
  end
end
