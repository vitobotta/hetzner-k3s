require "./volume/host_path"

class Kubernetes::Resources::Pod
  class Spec
    class Volume
      include YAML::Serializable
      include YAML::Serializable::Unmapped

      property name : String?
      property hostPath : HostPath?
    end
  end
end
