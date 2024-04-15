class Kubernetes::Resources::Pod
  class Spec
    class Toleration
      include YAML::Serializable
      include YAML::Serializable::Unmapped

      property effect : String?
      property key : String?
      property value : String?

      def initialize(@effect, @key, @value)
      end
    end
  end
end
