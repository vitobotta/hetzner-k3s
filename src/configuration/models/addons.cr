require "./addons_config/cluster_autoscaler"
require "./addons_config/csi_driver"
require "./addons_config/cloud_controller_manager"
require "./addons_config/system_upgrade_controller"
require "./addons_config/embedded_registry_mirror"

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
      getter traefik : Toggle = Toggle.new(false)
      getter servicelb : Toggle = Toggle.new(false)
      getter metrics_server : Toggle = Toggle.new(false)
      getter local_path_storage_class : Toggle = Toggle.new(false)

      # Addons with more complex configuration options
      getter csi_driver : Configuration::Models::AddonsConfig::CSIDriver = Configuration::Models::AddonsConfig::CSIDriver.new
      getter cluster_autoscaler : Configuration::Models::AddonsConfig::ClusterAutoscaler = Configuration::Models::AddonsConfig::ClusterAutoscaler.new
      getter cloud_controller_manager : Configuration::Models::AddonsConfig::CloudControllerManager = Configuration::Models::AddonsConfig::CloudControllerManager.new
      getter system_upgrade_controller : Configuration::Models::AddonsConfig::SystemUpgradeController = Configuration::Models::AddonsConfig::SystemUpgradeController.new
      getter embedded_registry_mirror : Configuration::Models::AddonsConfig::EmbeddedRegistryMirror = Configuration::Models::AddonsConfig::EmbeddedRegistryMirror.new

      def initialize
      end
    end
  end
end
