require "../../util"

class Kubernetes::Software::Hetzner::Secret
  include Kubernetes::Util

  HETZNER_CLOUD_SECRET_MANIFEST = {{ read_file("#{__DIR__}/../../../../templates/hetzner_cloud_secret_manifest.yaml") }}

  getter configuration : Configuration::Loader
  getter settings : Configuration::Main { configuration.settings }

  def initialize(@configuration, @settings)
  end

  def create
    puts "\n[Hetzner Cloud Secret] Creating secret for Hetzner Cloud token..."

    secret_manifest = Crinja.render(HETZNER_CLOUD_SECRET_MANIFEST, {
      network: (settings.existing_network || settings.cluster_name),
      token: settings.hetzner_token
    })

    apply_manifest(yaml: secret_manifest, prefix: "Hetzner Cloud Secret", error_message: "Failed to create Hetzner Cloud Secret")

    puts "[Hetzner Cloud Secret] ...secret created"
  end
end
