require "./pod/spec"

module Kubernetes::Resources
  class Pod
    include YAML::Serializable
    include YAML::Serializable::Unmapped

    property spec : Kubernetes::Resources::Pod::Spec
  end
end
