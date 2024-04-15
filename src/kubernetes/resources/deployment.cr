require "./deployment/spec"

module Kubernetes::Resources
  class Deployment
    include YAML::Serializable
    include YAML::Serializable::Unmapped

    property spec : Kubernetes::Resources::Deployment::Spec
  end
end
