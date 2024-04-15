module Kubernetes::Resources
  class Resource
    include YAML::Serializable
    include YAML::Serializable::Unmapped

    property kind : String
  end
end
