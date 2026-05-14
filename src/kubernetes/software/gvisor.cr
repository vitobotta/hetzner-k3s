require "../../configuration/loader"
require "../../configuration/main"
require "../../util"
require "../util"

class Kubernetes::Software::GVisor
  include Util
  include Kubernetes::Util

  private getter configuration : Configuration::Loader
  private getter settings : Configuration::Main { configuration.settings }

  def initialize(@configuration : Configuration::Loader, @settings : Configuration::Main)
  end

  def install : Nil
    log_line "Creating gVisor RuntimeClass...", log_prefix: default_log_prefix

    manifest = build_runtime_class_manifest
    apply_manifest_from_yaml(manifest, "Failed to create gVisor RuntimeClass")

    log_line "...gVisor RuntimeClass created", log_prefix: default_log_prefix
  end

  private def build_runtime_class_manifest : String
    <<-YAML
    apiVersion: node.k8s.io/v1
    kind: RuntimeClass
    metadata:
      name: gvisor
    handler: runsc
    YAML
  end

  private def default_log_prefix : String
    "gVisor"
  end
end
