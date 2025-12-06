module Configuration
  module Models
    module AddonsConfig
      class SystemUpgradeController
        include YAML::Serializable
        include YAML::Serializable::Unmapped

        getter enabled : Bool
        getter deployment_manifest_url : String = "https://github.com/rancher/system-upgrade-controller/releases/download/v0.18.0/system-upgrade-controller.yaml"
        getter crd_manifest_url : String = "https://github.com/rancher/system-upgrade-controller/releases/download/v0.18.0/crd.yaml"

        def initialize(@enabled : Bool = true)
        end

        def enabled?
          enabled
        end
      end
    end
  end
end
