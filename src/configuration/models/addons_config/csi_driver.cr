module Configuration
  module Models
    module AddonsConfig
      class CSIDriver
        include YAML::Serializable
        include YAML::Serializable::Unmapped

        getter enabled : Bool
        getter manifest_url : String = "https://raw.githubusercontent.com/hetznercloud/csi-driver/v2.12.0/deploy/kubernetes/hcloud-csi.yml"

        def initialize(@enabled : Bool = true)
        end

        def enabled?
          enabled
        end
      end
    end
  end
end
