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
    end
  end
end
