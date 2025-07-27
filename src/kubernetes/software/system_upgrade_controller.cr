require "../resources/resource"
require "../resources/deployment"
require "../resources/pod/spec/toleration"
require "../../configuration/loader"
require "../../configuration/main"
require "../../util"
require "../util"

class Kubernetes::Software::SystemUpgradeController
  include Util
  include Kubernetes::Util

  getter configuration : Configuration::Loader
  getter settings : Configuration::Main { configuration.settings }

  def initialize(@configuration : Configuration::Loader, @settings : Configuration::Main)
  end

  def install : Nil
    log_line "Installing System Upgrade Controller...", log_prefix: default_log_prefix

    create_namespace
    create_crd
    create_resources

    log_line "...System Upgrade Controller installed", log_prefix: default_log_prefix
  end

  private def create_namespace : Nil
    command = "kubectl create ns system-upgrade --dry-run=client -o yaml | kubectl apply -f -"
    apply_kubectl_command(command, "Failed to create system-upgrade namespace")
  end

  private def create_crd : Nil
    crd_url = settings.manifests.system_upgrade_controller_crd_manifest_url
    apply_manifest_from_url(crd_url, "Failed to apply System Upgrade Controller CRD")
  end

  private def create_resources : Nil
    manifest = fetch_deployment_manifest
    patched_manifest = patch_deployment_manifest(manifest)
    apply_manifest_from_yaml(patched_manifest, "Failed to apply System Upgrade Controller resources")
  end

  private def fetch_deployment_manifest : String
    deployment_url = settings.manifests.system_upgrade_controller_deployment_manifest_url
    fetch_manifest(deployment_url)
  end

  private def patch_deployment_manifest(manifest : String) : String
    resources = YAML.parse_all(manifest)
    patched_resources = apply_tolerations_to_deployments(resources)
    patched_resources.map(&.to_yaml).join("---\n")
  end

  private def deployment_with_added_toleration(resource : YAML::Any) : Kubernetes::Resources::Deployment
    deployment = Kubernetes::Resources::Deployment.from_yaml(resource.to_yaml)
    deployment.spec.template.spec.add_toleration(
      key: "CriticalAddonsOnly", 
      value: "true", 
      effect: "NoExecute"
    )
    deployment
  end

  private def apply_tolerations_to_deployments(resources : Array(YAML::Any)) : Array(YAML::Any)
    resources.map do |resource|
      parsed_resource = Kubernetes::Resources::Resource.from_yaml(resource.to_yaml)
      
      if parsed_resource.kind == "Deployment"
        patched_deployment = deployment_with_added_toleration(resource)
        YAML.parse(patched_deployment.to_yaml)
      else
        resource
      end
    end
  end

  private def default_log_prefix : String
    "System Upgrade Controller"
  end
end
