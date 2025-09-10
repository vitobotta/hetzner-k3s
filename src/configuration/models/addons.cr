require "./addons_config/cluster_autoscaler"

module Configuration
  module Models
    class Addons
      include YAML::Serializable
      include YAML::Serializable::Unmapped

      # Generic toggle struct - can be extended later with more settings per addon
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

      # Addons with simple configuration options
      getter csi_driver : Toggle = Toggle.new(true)
      getter traefik : Toggle = Toggle.new(false)
      getter servicelb : Toggle = Toggle.new(false)
      getter metrics_server : Toggle = Toggle.new(false)
      getter cloud_controller_manager : Toggle = Toggle.new(true)
      getter embedded_registry_mirror : Toggle = Toggle.new(true)
      getter local_path_storage_class : Toggle = Toggle.new(false)
      
      # Addons with more complex configuration options
      getter cluster_autoscaler : Configuration::Models::AddonsConfig::ClusterAutoscaler = Configuration::Models::AddonsConfig::ClusterAutoscaler.new

      def initialize
      end
    end
  end
end
