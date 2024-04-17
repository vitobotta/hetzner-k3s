require "../../../util"
require "../../util"

class Kubernetes::Software::Hetzner::CloudControllerManager
  include Util
  include Kubernetes::Util

  getter configuration : Configuration::Loader
  getter settings : Configuration::Main { configuration.settings }

  def initialize(@configuration, @settings)
  end

  def install
    log_line "Installing Hetzner Cloud Controller Manager..."

    apply_manifest_from_yaml(manifest)

    log_line "Hetzner Cloud Controller Manager installed"
  end

  private def default_log_prefix
    "Hetzner Cloud Controller"
  end

  private def manifest
    manifest = fetch_manifest(settings.cloud_controller_manager_manifest_url)
    manifest.gsub(/--cluster-cidr=[^"]+/, "--cluster-cidr=#{settings.cluster_cidr}")
  end
end
