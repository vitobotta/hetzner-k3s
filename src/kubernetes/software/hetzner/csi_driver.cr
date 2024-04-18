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

    apply_manifest_from_url(settings.manifests.csi_driver_manifest_url)

    log_line "Hetzner CSI Driver installed"
  end

  private def default_log_prefix
    "Hetzner CSI Driver"
  end
end
