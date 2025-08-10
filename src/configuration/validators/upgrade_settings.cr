require "./kubeconfig_path"
require "./new_k3s_version"
require "./kubectl_presence"

class Configuration::Validators::UpgradeSettings
  getter errors : Array(String) = [] of String
  getter settings : Configuration::Main
  getter kubeconfig_path : String
  getter new_k3s_version : String?

  def initialize(@errors, @settings, @kubeconfig_path, @new_k3s_version)
  end

  def validate
    Configuration::Validators::KubeconfigPath.new(errors, kubeconfig_path, file_must_exist: true).validate

    Configuration::Validators::NewK3sVersion.new(errors, settings.k3s_version, new_k3s_version).validate

    Configuration::Validators::KubectlPresence.new(errors).validate
  end
end
