require "../../util"

class Kubernetes::Software::Hetzner::CSIDriver
  include Kubernetes::Util

  getter configuration : Configuration::Loader
  getter settings : Configuration::Main { configuration.settings }

  def initialize(@configuration, @settings)
  end

  def install
    puts "\n[Hetzner CSI Driver] Installing Hetzner CSI Driver..."

    apply_manifest(url: settings.csi_driver_manifest_url, prefix: "Hetzner CSI Driver", error_message: "Failed to install Hetzner CSI Driver")

    puts "[Hetzner CSI Driver] ...CSI Driver installed"
  end
end
