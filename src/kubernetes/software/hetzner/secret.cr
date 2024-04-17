require "../../../util"
require "../../util"

class Kubernetes::Software::Hetzner::Secret
  include Util
  include Kubernetes::Util

  HETZNER_CLOUD_SECRET_MANIFEST = {{ read_file("#{__DIR__}/../../../../templates/hetzner_cloud_secret_manifest.yaml") }}

  getter configuration : Configuration::Loader
  getter settings : Configuration::Main { configuration.settings }

  def initialize(@configuration, @settings)
  end

  def create
    log_line "Creating secret for Hetzner Cloud token..."

    secret_manifest = Crinja.render(HETZNER_CLOUD_SECRET_MANIFEST, {
      network: (settings.existing_network || settings.cluster_name),
      token: settings.hetzner_token
    })

    apply_manifest_from_yaml(secret_manifest)

    log_line "...secret created"
  end

  private def default_log_prefix
    "Hetzner Cloud Secret"
  end
end
