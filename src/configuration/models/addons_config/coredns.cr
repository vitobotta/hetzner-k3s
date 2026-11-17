module Configuration
  module Models
    module AddonsConfig
      # CoreDNS ships with k3s. When enabled is true, hetzner-k3s disables the packaged manifest
      # and deploys its own copy rendered from templates/coredns.yaml, which allows changing the
      # replica count, the container resources and the image. When false, k3s keeps managing
      # CoreDNS and only the replica count is reconciled.
      class CoreDNS
        include YAML::Serializable
        include YAML::Serializable::Unmapped

        # Same image as the k3s manifest of the k3s version this tool was released against.
        DEFAULT_IMAGE = "rancher/mirrored-coredns-coredns:1.12.0"

        getter enabled : Bool = false
        # Only enforced when set: with the toggle off an unset value leaves a manual scale alone.
        getter replicas : Int32?
        getter image : String = DEFAULT_IMAGE
        getter resources : Resources = Resources.new

        def initialize(@enabled : Bool = false, @replicas : Int32? = nil, @image : String = DEFAULT_IMAGE, @resources : Resources = Resources.new)
        end

        def enabled?
          enabled
        end

        class Resources
          include YAML::Serializable
          include YAML::Serializable::Unmapped

          getter requests : Quantity = Quantity.new
          getter limits : Quantity = Quantity.new

          def initialize(@requests : Quantity = Quantity.new, @limits : Quantity = Quantity.new)
          end
        end

        class Quantity
          include YAML::Serializable
          include YAML::Serializable::Unmapped

          getter cpu : String?
          getter memory : String?

          def initialize(@cpu : String? = nil, @memory : String? = nil)
          end
        end
      end
    end
  end
end
