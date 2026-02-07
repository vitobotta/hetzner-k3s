class Kubernetes::Resources::Pod
  class Spec
    class Volume
      class ConfigMap
        include YAML::Serializable
        include YAML::Serializable::Unmapped

        property name : String?

        def initialize(@name : String? = nil)
        end
      end
    end
  end
end
