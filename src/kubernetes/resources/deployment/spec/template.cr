require "../../pod/spec"

module Kubernetes::Resources
  class Deployment
    class Spec
      class Template
        include YAML::Serializable
        include YAML::Serializable::Unmapped

        property spec : Kubernetes::Resources::Pod::Spec
      end
    end
  end
end
