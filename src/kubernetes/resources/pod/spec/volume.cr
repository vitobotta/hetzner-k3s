require "./volume/host_path"
require "./volume/config_map"

class Kubernetes::Resources::Pod
  class Spec
    class Volume
      include YAML::Serializable
      include YAML::Serializable::Unmapped

      property name : String?
      property hostPath : HostPath?
      property configMap : ConfigMap?

      def initialize(@name : String? = nil, @hostPath : HostPath? = nil, @configMap : ConfigMap? = nil)
      end
    end
  end
end
