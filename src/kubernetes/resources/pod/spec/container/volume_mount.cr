class Kubernetes::Resources::Pod
  class Spec
    class Container
      class VolumeMount
        include YAML::Serializable
        include YAML::Serializable::Unmapped

        property name : String?
        property mountPath : String?
        property readOnly : Bool?

        def initialize(@name, @mountPath, @readOnly)
        end
      end
    end
  end
end
