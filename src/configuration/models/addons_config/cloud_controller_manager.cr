module Configuration
  module Models
    module AddonsConfig
      class CloudControllerManager
        include YAML::Serializable
        include YAML::Serializable::Unmapped

        getter enabled : Bool
        getter manifest_url : String = "https://github.com/hetznercloud/hcloud-cloud-controller-manager/releases/download/v1.23.0/ccm-networks.yaml"

        def initialize(@enabled : Bool = true)
        end

        def enabled?
          enabled
        end
      end
    end
  end
end
