class Kubernetes::Software::Hetzner::Secret
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

    command = <<-BASH
    kubectl apply -f - <<-EOF
    #{secret_manifest}
    EOF
    BASH

    result = Util::Shell.run(command, configuration.kubeconfig_path, settings.hetzner_token, prefix: "Hetzner Cloud Secret")

    unless result.success?
      puts "Failed to create Hetzner Cloud secret:"
      puts result.output
      exit 1
    end

    puts "[Hetzner Cloud Secret] ...secret created"
  end
end
