require "crinja"
require "../util"
require "../util/shell"
require "../configuration/main"
require "../configuration/loader"

class Cluster::Upgrade
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
    puts "\n=== k3s version upgrade ===\n"

    Util.check_kubectl

    workers_count = settings.worker_node_pools.sum { |pool| pool.instance_count }
    worker_upgrade_concurrency = [(workers_count / 4).to_i, 1].max

    masters_upgrade_manifest = Crinja.render(UPGRADE_PLAN_MANIFEST_FOR_MASTERS, {
      new_k3s_version: new_k3s_version,
    })

    command = String.build do |str|
      str << "kubectl apply -f - <<-EOF\n"
      str << masters_upgrade_manifest.strip
      str << "\nEOF"
    end

    result = Util::Shell.run(command, configuration.kubeconfig_path, settings.hetzner_token)

    unless result.success?
      puts "Failed to create upgrade plan for controlplane:"
      puts result.output
      exit 1
    end

    if workers_count > 0
      workers_upgrade_manifest = Crinja.render(UPGRADE_PLAN_MANIFEST_FOR_WORKERS, {
        new_k3s_version: new_k3s_version,
        worker_upgrade_concurrency: worker_upgrade_concurrency,
      })

      command = String.build do |str|
        str << "kubectl apply -f - <<-EOF\n"
        str << workers_upgrade_manifest.strip
        str << "\nEOF"
      end

      result = Util::Shell.run(command, configuration.kubeconfig_path, settings.hetzner_token)

      unless result.success?
        puts "Failed to create upgrade plan for workers:"
        puts result.output
        exit 1
      end
    end

    puts "Upgrade will now start. Run `watch kubectl get nodes` to see the nodes being upgraded. This should take a few minutes for a small cluster."
    puts "The API server may be briefly unavailable during the upgrade of the controlplane."

    configuration_file_path = configuration.configuration_file_path
    current_configuration = File.read(configuration_file_path)
    new_configuration = current_configuration.gsub(/k3s_version: .*/, "k3s_version: #{new_k3s_version}")

    File.write(configuration_file_path, new_configuration)
  end
end
