require "./container/env_variable"
require "./container/volume_mount"

class Kubernetes::Resources::Pod
  class Spec
    class Container
      include YAML::Serializable
      include YAML::Serializable::Unmapped

      property name : String?
      property image : String?
      property command : Array(String)?
      property env : Array(EnvVariable)?
      property volumeMounts : Array(VolumeMount)?
    end
  end
end
