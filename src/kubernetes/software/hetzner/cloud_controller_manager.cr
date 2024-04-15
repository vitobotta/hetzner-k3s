class Kubernetes::Software::Hetzner::CloudControllerManager
  getter configuration : Configuration::Loader
  getter settings : Configuration::Main { configuration.settings }

  def initialize(@configuration, @settings)
  end

  def install
    puts "\n[Hetzner Cloud Controller] Installing Hetzner Cloud Controller Manager..."

    response = Crest.get(settings.cloud_controller_manager_manifest_url)

    unless response.success?
      puts "Failed to download CCM manifest from #{settings.cloud_controller_manager_manifest_url}"
      puts "Server responded with status #{response.status_code}"
      exit 1
    end

    ccm_manifest = response.body.to_s.gsub(/--cluster-cidr=[^"]+/, "--cluster-cidr=#{settings.cluster_cidr}")

    command = <<-BASH
    kubectl apply -f - <<-EOF
    #{ccm_manifest}
    EOF
    BASH

    result = Util::Shell.run(command, configuration.kubeconfig_path, settings.hetzner_token, prefix: "Hetzner Cloud Controller")

    unless result.success?
      puts "Failed to deploy Cloud Controller Manager:"
      puts result.output
      exit 1
    end

    puts "[Hetzner Cloud Controller] Hetzner Cloud Controller Manager installed"
  end
end
