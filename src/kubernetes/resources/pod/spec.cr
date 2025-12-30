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
        toleration = Kubernetes::Resources::Pod::Spec::Toleration.new(key: key, value: value, effect: effect)

        if tolerations = self.tolerations
          tolerations << toleration
        else
          self.tolerations = [toleration]
        end
      end

      def add_critical_addons_only_toleration
        add_toleration(key: "CriticalAddonsOnly", value: "true", effect: "NoExecute")
      end
    end
  end
end
