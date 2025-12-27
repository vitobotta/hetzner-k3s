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

    log_line "Hetzner Cloud Controller Manager installed", log_prefix: default_log_prefix
  end

  private def build_manifest_content : String
    manifest_url = resolve_manifest_url
    raw_manifest = fetch_manifest(manifest_url)
    patch_cluster_cidr(raw_manifest)
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

  private def default_log_prefix : String
    "Hetzner Cloud Controller Manager"
  end
end
