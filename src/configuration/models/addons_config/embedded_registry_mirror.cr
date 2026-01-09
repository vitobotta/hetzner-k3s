module Configuration
  module Models
    module AddonsConfig
      class EmbeddedRegistryMirror
        include YAML::Serializable
        include YAML::Serializable::Unmapped

        getter enabled : Bool
        getter private_registry_config : String = <<-YAML
          mirrors:
            "*":
          YAML

        def initialize(@enabled : Bool = true)
        end

        def enabled?
          enabled
        end
      end
    end
  end
end
