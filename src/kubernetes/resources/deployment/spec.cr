require "./spec/template"

module Kubernetes::Resources
  class Deployment
    class Spec
      include YAML::Serializable
      include YAML::Serializable::Unmapped

      property template : Kubernetes::Resources::Deployment::Spec::Template
    end
  end
end
