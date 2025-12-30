class Kubernetes::Resources::Pod
  class Spec
    class Container
      class VolumeMount
        include YAML::Serializable
        include YAML::Serializable::Unmapped

        property name : String?
        property mountPath : String?
        property readOnly : Bool?

        def initialize(@name : String? = nil, @mountPath : String? = nil, @readOnly : Bool? = nil)
        end
      end
    end
  end
end
