class Kubernetes::Software::Hetzner::CSIDriver
  getter configuration : Configuration::Loader
  getter settings : Configuration::Main { configuration.settings }

  def initialize(@configuration, @settings)
  end

  def install
    puts "\n[Hetzner CSI Driver] Installing Hetzner CSI Driver..."

    command = "kubectl apply -f #{settings.csi_driver_manifest_url}"

    result = Util::Shell.run(command, configuration.kubeconfig_path, settings.hetzner_token, prefix: "Hetzner CSI Driver")

    unless result.success?
      puts "Failed to deploy CSI Driver:"
      puts result.output
      exit 1
    end

    puts "[Hetzner CSI Driver] ...CSI Driver installed"
  end
end
