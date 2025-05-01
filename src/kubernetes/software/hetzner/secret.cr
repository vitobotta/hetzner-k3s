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

    network_name = if settings.networking.private_network.enabled
                     existing_network_name = settings.networking.private_network.existing_network_name
                     existing_network_name.empty? ? settings.cluster_name : existing_network_name
                   else
                     ""
                   end

    secret_manifest = Crinja.render(HETZNER_CLOUD_SECRET_MANIFEST, {
      network:        network_name,
      token:          settings.hetzner_token,
      robot_user:     settings.robot_user,
      robot_password: settings.robot_password,
    })

    apply_manifest_from_yaml(secret_manifest, "Failed to create Hetzner Cloud secret")

    log_line "...secret created"
  end

  private def default_log_prefix
    "Hetzner Cloud Secret"
  end
end
