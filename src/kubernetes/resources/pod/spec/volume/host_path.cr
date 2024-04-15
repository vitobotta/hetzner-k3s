class Kubernetes::Resources::Pod
  class Spec
    class Volume
      class HostPath
        include YAML::Serializable
        include YAML::Serializable::Unmapped

        property path : String?

        def initialize(@path)
        end
      end
    end
  end
end
