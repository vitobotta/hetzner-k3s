require "./container/env_variable"
require "./container/volume_mount"

class Kubernetes::Resources::Pod
  class Spec
    class Container
      include YAML::Serializable
      include YAML::Serializable::Unmapped

      property name : String?
      property command : String?
      property env : Array(EnvVariable)?
      property volumeMounts : Array(VolumeMount)?

      def initialize(@name, @command, @env, @volumeMounts)
      end
    end
  end
end
