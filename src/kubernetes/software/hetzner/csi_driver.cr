require "../../../util"
require "../../util"

class Kubernetes::Software::Hetzner::CSIDriver
  include Util
  include Kubernetes::Util

  private getter configuration : Configuration::Loader
  private getter settings : Configuration::Main { configuration.settings }

  def initialize(@configuration : Configuration::Loader, @settings : Configuration::Main)
  end

  def install : Nil
    log_line "Installing Hetzner CSI Driver...", log_prefix: default_log_prefix

    manifest_content = build_manifest_content
    apply_manifest_from_yaml(manifest_content, "Failed to install Hetzner CSI Driver")

    log_line "...Hetzner CSI Driver installed", log_prefix: default_log_prefix
  end

  private def build_manifest_content : String
    raw_manifest = fetch_manifest(settings.addons.csi_driver.manifest_url)
    manifest = patch_external_node_affinity(raw_manifest)
    patch_controller_default_location(manifest)
  end

  private def patch_external_node_affinity(manifest : String) : String
    return manifest unless external_node_pools?
    return manifest if manifest.includes?("key: hetzner-k3s.io/external")

    manifest_lines = manifest.lines(chomp: false)
    bounds = manifest_document_bounds(manifest_lines, "DaemonSet", "hcloud-csi-node")

    unless bounds
      log_line "Failed to patch the Hetzner CSI Driver manifest. The hcloud-csi-node DaemonSet was not found.", log_prefix: default_log_prefix
      exit 1
    end

    start_index, end_index = bounds
    tolerations_index = (start_index...end_index).find { |index| manifest_lines[index].match(/^[ \t]*tolerations:[ \t]*$/) }
    expression_index = (start_index...(tolerations_index || end_index)).to_a.reverse.find { |index| manifest_lines[index].match(/^[ \t]*-[ \t]+key:[ \t]+/) }

    unless tolerations_index && expression_index
      log_line "Failed to patch the Hetzner CSI Driver manifest. The hcloud-csi-node DaemonSet must expose node affinity match expressions.", log_prefix: default_log_prefix
      exit 1
    end

    expression_indent = leading_whitespace(manifest_lines[expression_index])
    manifest_lines.insert(tolerations_index, "#{expression_indent}- key: hetzner-k3s.io/external\n")
    manifest_lines.insert(tolerations_index + 1, "#{expression_indent}  operator: NotIn\n")
    manifest_lines.insert(tolerations_index + 2, "#{expression_indent}  values:\n")
    manifest_lines.insert(tolerations_index + 3, "#{expression_indent}  - \"true\"\n")
    manifest_lines.join
  end

  private def patch_controller_default_location(manifest : String) : String
    return manifest unless external_node_pools?
    return manifest if manifest.includes?("name: HCLOUD_VOLUME_DEFAULT_LOCATION")

    manifest_lines = manifest.lines(chomp: false)
    bounds = manifest_document_bounds(manifest_lines, "Deployment", "hcloud-csi-controller")

    unless bounds
      log_line "Failed to patch the Hetzner CSI Driver manifest. The hcloud-csi-controller Deployment was not found.", log_prefix: default_log_prefix
      exit 1
    end

    start_index, end_index = bounds
    csi_endpoint_index = (start_index...end_index).find { |index| manifest_lines[index].match(/^[ \t]*-[ \t]+name:[ \t]+CSI_ENDPOINT[ \t]*$/) }

    unless csi_endpoint_index
      log_line "Failed to patch the Hetzner CSI Driver manifest. The hcloud-csi-controller Deployment must expose CSI_ENDPOINT in the controller environment.", log_prefix: default_log_prefix
      exit 1
    end

    item_indent = leading_whitespace(manifest_lines[csi_endpoint_index])
    insertion_index = env_item_end_index(manifest_lines, csi_endpoint_index, item_indent.size)

    manifest_lines.insert(insertion_index, "#{item_indent}- name: HCLOUD_VOLUME_DEFAULT_LOCATION\n")
    manifest_lines.insert(insertion_index + 1, "#{item_indent}  value: \"#{settings.masters_pool.locations.first}\"\n")
    manifest_lines.join
  end

  private def manifest_document_bounds(lines : Array(String), kind : String, name : String) : Tuple(Int32, Int32)?
    start_index = 0

    while start_index < lines.size
      end_index = next_manifest_document_index(lines, start_index)
      document_lines = lines[start_index...end_index]

      if document_lines.any? { |line| line.strip == "kind: #{kind}" } &&
         document_lines.any? { |line| line.match(/^[ \t]*name:[ \t]+#{Regex.escape(name)}[ \t]*$/) }
        return {start_index, end_index}
      end

      start_index = end_index + 1
    end

    nil
  end

  private def env_item_end_index(lines : Array(String), start_index : Int32, item_indent_size : Int32) : Int32
    index = start_index + 1

    while index < lines.size
      line = lines[index]
      stripped_line = line.strip

      if stripped_line.empty?
        index += 1
        next
      end

      break if leading_whitespace(line).size <= item_indent_size

      index += 1
    end

    index
  end

  private def next_manifest_document_index(lines : Array(String), start_index : Int32) : Int32
    index = start_index + 1

    while index < lines.size && lines[index].strip != "---"
      index += 1
    end

    index
  end

  private def external_node_pools? : Bool
    settings.worker_node_pools.any?(&.external?)
  end

  private def leading_whitespace(line : String) : String
    line.match(/^[ \t]*/).not_nil![0]
  end

  private def default_log_prefix : String
    "Hetzner CSI Driver"
  end
end
