require "../../../util"
require "../../util"

class Kubernetes::Software::Hetzner::CloudControllerManager
  include Util
  include Kubernetes::Util

  private getter configuration : Configuration::Loader
  private getter settings : Configuration::Main { configuration.settings }

  def initialize(@configuration : Configuration::Loader, @settings : Configuration::Main)
  end

  def install : Nil
    log_line "Installing Hetzner Cloud Controller Manager...", log_prefix: default_log_prefix

    manifest_content = build_manifest_content
    apply_manifest_from_yaml(manifest_content, "Failed to install Hetzner Cloud Controller Manager")
    wait_for_rollout_if_needed

    log_line "Hetzner Cloud Controller Manager installed", log_prefix: default_log_prefix
  end

  private def build_manifest_content : String
    manifest_url = resolve_manifest_url
    raw_manifest = fetch_manifest(manifest_url)
    manifest = patch_cluster_cidr(raw_manifest)
    patch_robot_enabled(manifest)
  end

  private def resolve_manifest_url : String
    base_url = settings.addons.cloud_controller_manager.manifest_url

    if settings.networking.private_network.enabled
      base_url
    else
      base_url.gsub("-networks", "")
    end
  end

  private def patch_cluster_cidr(manifest : String) : String
    cluster_cidr = settings.networking.cluster_cidr
    manifest.gsub(/--cluster-cidr=[^"]+/, "--cluster-cidr=#{cluster_cidr}")
  end

  private def patch_robot_enabled(manifest : String) : String
    return manifest unless settings.external_robot_node_pools?
    return manifest if manifest.includes?("name: ROBOT_ENABLED")

    manifest_lines = manifest.lines(chomp: false)
    robot_user_line_index = manifest_lines.index { |line| line.match(/^[ \t]*-[ \t]+name:[ \t]+ROBOT_USER[ \t]*$/) }

    unless robot_user_line_index
      log_line "Failed to enable Robot support in the Hetzner Cloud Controller Manager manifest. The manifest must expose ROBOT_USER from the hcloud secret.", log_prefix: default_log_prefix
      exit 1
    end

    item_indent = leading_whitespace(manifest_lines[robot_user_line_index])
    insertion_index = env_item_end_index(manifest_lines, robot_user_line_index, item_indent.size)

    manifest_lines.insert(insertion_index, "#{item_indent}- name: ROBOT_ENABLED\n")
    manifest_lines.insert(insertion_index + 1, "#{item_indent}  value: \"true\"\n")
    manifest_lines.join
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

  private def leading_whitespace(line : String) : String
    line.match(/^[ \t]*/).not_nil![0]
  end

  private def wait_for_rollout_if_needed : Nil
    return unless settings.external_robot_node_pools?

    log_line "Waiting for Hetzner Cloud Controller Manager rollout...", log_prefix: default_log_prefix
    apply_kubectl_command(
      "kubectl -n kube-system rollout status deployment/hcloud-cloud-controller-manager --timeout=180s",
      "Hetzner Cloud Controller Manager did not become ready"
    )
  end

  private def default_log_prefix : String
    "Hetzner Cloud Controller Manager"
  end
end
