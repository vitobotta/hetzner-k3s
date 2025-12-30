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

    apply_manifest_from_url(settings.addons.csi_driver.manifest_url, "Failed to install Hetzner CSI Driver")

    log_line "...Hetzner CSI Driver installed", log_prefix: default_log_prefix
  end

  private def default_log_prefix : String
    "Hetzner CSI Driver"
  end
end
