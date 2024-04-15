require "../../../pod/spec/toleration"

module Kubernetes::Resources
  class Deployment
    class Spec
      class Template
        class Spec
          include YAML::Serializable
          include YAML::Serializable::Unmapped

          property tolerations : Array(Kubernetes::Resources::Pod::Spec::Toleration)?
        end
      end
    end
  end
end
