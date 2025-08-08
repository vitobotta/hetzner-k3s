module Configuration
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

    # Addon definitions with sensible defaults
    getter csi_driver : Toggle = Toggle.new(true)
    getter traefik : Toggle = Toggle.new(false)
    getter servicelb : Toggle = Toggle.new(false)
    getter metrics_server : Toggle = Toggle.new(false)
    getter cloud_controller_manager : Toggle = Toggle.new(true)

    # Additional configurable addons
    getter embedded_registry_mirror : Configuration::EmbeddedRegistryMirror = Configuration::EmbeddedRegistryMirror.new
    getter local_path_storage_class : Configuration::LocalPathStorageClass = Configuration::LocalPathStorageClass.new
    getter cluster_autoscaler : Configuration::ClusterAutoscaler = Configuration::ClusterAutoscaler.new

    def initialize
    end
  end
end 