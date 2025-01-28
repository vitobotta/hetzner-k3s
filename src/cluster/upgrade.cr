require "crinja"
require "../util"
require "../util/shell"
require "../kubernetes/util"
require "../configuration/main"
require "../configuration/loader"

class Cluster::Upgrade
  include Util
  include Util::Shell
  include Kubernetes::Util

  UPGRADE_PLAN_MANIFEST_FOR_MASTERS = {{ read_file("#{__DIR__}/../../templates/upgrade_plan_for_masters.yaml") }}
  UPGRADE_PLAN_MANIFEST_FOR_WORKERS = {{ read_file("#{__DIR__}/../../templates/upgrade_plan_for_workers.yaml") }}

  getter configuration : Configuration::Loader
  getter settings : Configuration::Main do
    configuration.settings
  end
  getter new_k3s_version : String? do
    configuration.new_k3s_version
  end

  def initialize(@configuration)
  end

  def run
    print "Please enter the cluster name to confirm that you want to upgrade it: "
    input = gets

    if input.try(&.strip) != settings.cluster_name
      puts "Cluster name '#{input.try(&.strip)}' does not match '#{settings.cluster_name}'. Aborting upgrade."
      exit 1
    end

    log_line "k3s version upgrade started"

    ensure_kubectl_is_installed!

    create_upgrade_plan_for_controlplane
    create_upgrade_plan_for_workers

    log_line "Upgrade will now start. Run `watch kubectl get nodes` to see the nodes being upgraded. This should take a few minutes for a small cluster."
    log_line "The API server may be briefly unavailable during the upgrade of the controlplane."

    update_k3s_version_in_configuration_file
  end

  private def default_log_prefix
    "K3s upgrade"
  end

  private def masters_upgrade_manifest
    Crinja.render(UPGRADE_PLAN_MANIFEST_FOR_MASTERS, {
      new_k3s_version: new_k3s_version,
    })
  end

  private def worker_upgrade_concurrency
    [(workers_count / 4).to_i, 1].max
  end

  private def workers_count
    result = run_shell_command("kubectl get nodes | grep -v master | tail -n +2", configuration.kubeconfig_path, settings.hetzner_token, print_output: false)
    result.output.split("\n").size
  end

  private def create_upgrade_plan_for_controlplane
    command = String.build do |str|
      str << "kubectl apply -f - <<-EOF\n"
      str << masters_upgrade_manifest.strip
      str << "\nEOF"
    end

    run_shell_command command, configuration.kubeconfig_path, settings.hetzner_token, error_message: "Failed to create upgrade plan for controlplane"
  end

  private def create_upgrade_plan_for_workers
    return if workers_count.zero?

    workers_upgrade_manifest = Crinja.render(UPGRADE_PLAN_MANIFEST_FOR_WORKERS, {
      new_k3s_version: new_k3s_version,
      worker_upgrade_concurrency: worker_upgrade_concurrency,
    })

    command = String.build do |str|
      str << "kubectl apply -f - <<-EOF\n"
      str << workers_upgrade_manifest.strip
      str << "\nEOF"
    end

    run_shell_command command, configuration.kubeconfig_path, settings.hetzner_token, error_message: "Failed to create upgrade plan for workers"
  end

  private def update_k3s_version_in_configuration_file
    current_configuration = File.read(configuration.configuration_file_path)
    new_configuration = current_configuration.gsub(/k3s_version: .*/, "k3s_version: #{new_k3s_version}")

    File.write(configuration.configuration_file_path, new_configuration)
  end
end
