require "../resources/resource"
require "../resources/deployment"
require "../resources/pod/spec/toleration"
require "../../configuration/loader"
require "../../configuration/main"

class Kubernetes::Software::SystemUpgradeController
  getter configuration : Configuration::Loader
  getter settings : Configuration::Main { configuration.settings }

  def initialize(@configuration, @settings)

  end

  def install
    puts "\n[System Upgrade Controller] Deploying k3s System Upgrade Controller..."

    create_namespace
    create_crd
    create_resources

    puts "[System Upgrade Controller] ...k3s System Upgrade Controller deployed."
  end

  private def create_namespace
    run_command "kubectl create ns system-upgrade --dry-run=client -o yaml | kubectl apply -f -"
  end

  private def create_crd
    run_command "kubectl apply -f #{settings.system_upgrade_controller_crd_manifest_url}"
  end

  private def create_resources
    manifest = fetch_resources_manifest
    resources = YAML.parse_all(manifest)
    patched_resources = patch_resources(resources)
    patched_manifest = patched_resources.map(&.to_yaml).join
    updated_manifest_path = "/tmp/manifest.yaml"

    File.write(updated_manifest_path, patched_manifest)

    run_command "kubectl apply -f #{updated_manifest_path}"

    File.delete(updated_manifest_path)
  end

  private def fetch_resources_manifest
    response = Crest.get(settings.system_upgrade_controller_deployment_manifest_url)

    unless response.success?
      puts "[System Upgrade Controller] Failed to download System Upgrade Controller manifest from #{settings.system_upgrade_controller_deployment_manifest_url}"
      puts "[System Upgrade Controller] Server responded with status #{response.status_code}"
      exit 1
    end

    response.body.to_s
  end

  private def deployment_with_added_toleration(resource)
    deployment = Kubernetes::Resources::Deployment.from_yaml(resource.to_yaml)
    toleration = Kubernetes::Resources::Pod::Spec::Toleration.new(effect: "NoExecute", key: "CriticalAddonsOnly", value: "true")

    if tolerations = deployment.spec.template.spec.tolerations
      tolerations << toleration
    else
      deployment.spec.template.spec.tolerations = [toleration]
    end

    deployment
  end

  private def run_command(command)
    result = Util::Shell.run(command, configuration.kubeconfig_path, settings.hetzner_token, prefix: "System Upgrade Controller")

    unless result.success?
      puts "[System Upgrade Controller] Failed to deploy k3s System Upgrade Controller:"
      puts result.output
      exit 1
    end
  end

  private def patch_resources(resources)
    resources.map do |resource|
      resource = Kubernetes::Resources::Resource.from_yaml(resource.to_yaml)

      if resource.kind == "Deployment"
        deployment_with_added_toleration(resource)
      else
        resource
      end
    end
  end
end
