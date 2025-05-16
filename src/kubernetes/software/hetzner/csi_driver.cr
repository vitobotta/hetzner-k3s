require "../../../util"
require "../../util"

class Kubernetes::Software::Hetzner::CSIDriver
  include Util
  include Kubernetes::Util

  getter configuration : Configuration::Loader
  getter settings : Configuration::Main { configuration.settings }

  def initialize(@configuration, @settings)
  end

  def install
    log_line "Installing Hetzner CSI Driver..."
    apply_manifest_from_yaml(manifest, "Failed to install Hetzner CSI Driver")

    log_line "Hetzner CSI Driver installed"
  end

  private def default_log_prefix
    "Hetzner CSI Driver"
  end

  private def manifest
    manifest = fetch_manifest(settings.manifests.csi_driver_manifest_url)

    documents = YAML.parse_all(manifest)

    documents.each do |doc|
      next unless doc["kind"]?.try(&.as_s) == "DaemonSet"
      next unless doc["metadata"]?.try(&.["name"]?.try(&.as_s)) == "hcloud-csi-node"

      spec = doc["spec"]?
      next unless spec_h = spec.try(&.as_h?)

      template = spec_h["template"]?
      next unless template_h = template.try(&.as_h?)

      spec = template_h["spec"]?
      next unless spec_h = spec.try(&.as_h?)

      node_selector = spec_h["nodeSelector"]?.try(&.as_h?) || begin
        new_selector = {} of YAML::Any => YAML::Any
        spec_h[YAML::Any.new("nodeSelector")] = YAML::Any.new(new_selector)
        new_selector
      end

      node_selector[YAML::Any.new("instance.hetzner.cloud/provided-by")] = YAML::Any.new("cloud")
    end

    documents.map(&.to_yaml).join("---\n")
  end
end
