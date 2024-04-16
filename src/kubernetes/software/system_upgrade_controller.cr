require "../resources/resource"
require "../resources/deployment"
require "../resources/pod/spec/toleration"
require "../../configuration/loader"
require "../../configuration/main"
require "../util"

class Kubernetes::Software::SystemUpgradeController
  include Kubernetes::Util

  getter configuration : Configuration::Loader
  getter settings : Configuration::Main { configuration.settings }

  def initialize(@configuration, @settings)
  end

  def install
    puts "\n[System Upgrade Controller] Installing k3s System Upgrade Controller..."

    create_namespace
    create_crd
    create_resources

    puts "[System Upgrade Controller] ...System Upgrade Controller installed."
  end

  private def create_namespace
    command = "kubectl create ns system-upgrade --dry-run=client -o yaml | kubectl apply -f -"
    apply_kubectl_command(command, prefix = "System Upgrade Controller", error_message = "Failed to install System Upgrade Controller")
  end

  private def create_crd
    apply_manifest(url: settings.system_upgrade_controller_crd_manifest_url, prefix: "System Upgrade Controller", error_message: "Failed to install System Upgrade Controller")
  end

  private def create_resources
    manifest = fetch_resources_manifest
    resources = YAML.parse_all(manifest)
    patched_resources = patch_resources(resources)
    patched_manifest = patched_resources.map(&.to_yaml).join

    apply_manifest(yaml: patched_manifest, prefix: "System Upgrade Controller", error_message: "Failed to install System Upgrade Controller")
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

    deployment.spec.template.spec.add_toleration(key: "CriticalAddonsOnly", value: "true", effect: "NoExecute")

    deployment
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
