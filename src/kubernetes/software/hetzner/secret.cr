require "../../../util"
require "../../util"

class Kubernetes::Software::Hetzner::Secret
  include Util
  include Kubernetes::Util

  HETZNER_CLOUD_SECRET_MANIFEST = {{ read_file("#{__DIR__}/../../../../templates/hetzner_cloud_secret_manifest.yaml") }}

  private getter configuration : Configuration::Loader
  private getter settings : Configuration::Main { configuration.settings }

  def initialize(@configuration : Configuration::Loader, @settings : Configuration::Main)
  end

  def create : Nil
    log_line "Creating secret for Hetzner Cloud token...", log_prefix: default_log_prefix

    secret_manifest = build_secret_manifest
    apply_manifest_from_yaml(secret_manifest, "Failed to create Hetzner Cloud secret")

    log_line "...secret created", log_prefix: default_log_prefix
  end

  private def build_secret_manifest : String
    network_name = resolve_network_name

    Crinja.render(HETZNER_CLOUD_SECRET_MANIFEST, {
      network: network_name,
      token:   settings.hetzner_token,
    })
  end

  private def resolve_network_name : String
    return "" unless settings.networking.private_network.enabled

    existing_name = settings.networking.private_network.existing_network_name
    existing_name.blank? ? settings.cluster_name : existing_name
  end

  private def default_log_prefix : String
    "Hetzner Cloud Secret"
  end
end
