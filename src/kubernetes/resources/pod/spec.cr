require "./spec/toleration"

module Kubernetes::Resources
  class Pod
    class Spec
      include YAML::Serializable
      include YAML::Serializable::Unmapped

      property tolerations : Array(Kubernetes::Resources::Pod::Spec::Toleration)?
    end
  end
end
