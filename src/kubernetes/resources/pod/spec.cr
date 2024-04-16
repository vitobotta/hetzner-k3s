require "./spec/toleration"
require "./spec/container"
require "./spec/volume"

module Kubernetes::Resources
  class Pod
    class Spec
      include YAML::Serializable
      include YAML::Serializable::Unmapped

      property tolerations : Array(Kubernetes::Resources::Pod::Spec::Toleration)?
      property containers : Array(Kubernetes::Resources::Pod::Spec::Container)?
      property volumes : Array(Kubernetes::Resources::Pod::Spec::Volume)?

      def add_toleration(key, value, effect)
        toleration = Kubernetes::Resources::Pod::Spec::Toleration.new(key, value, effect)

        if tolerations = self.tolerations
          tolerations << toleration
        else
          self.tolerations = [toleration]
        end
      end
    end
  end
end
