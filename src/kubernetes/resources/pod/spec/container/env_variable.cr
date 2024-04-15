class Kubernetes::Resources::Pod
  class Spec
    class Container
      class EnvVariable
        include YAML::Serializable
        include YAML::Serializable::Unmapped

        property name : String?
        property value : String?

        def initialize(@name, @value)
        end
      end
    end
  end
end
