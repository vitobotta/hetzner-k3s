require "../util"
require "../util/shell"
require "../configuration/main"
require "../configuration/loader"

class Cluster::Upgrade
  private getter configuration : Configuration::Loader
  private getter settings : Configuration::Main do
    configuration.settings
  end

  def initialize(@configuration)
  end

  def run
    puts "\n=== k3s version upgrade ===\n"

    Util.check_kubectl

    workers_count = settings.worker_node_pools.sum { |pool| pool.instance_count }
    worker_upgrade_concurrency = workers_count - 1
    worker_upgrade_concurrency = 1 if worker_upgrade_concurrency.zero?
    new_k3s_version = configuration.new_k3s_version

    command = <<-BASH
    kubectl apply -f - <<-EOF
      apiVersion: upgrade.cattle.io/v1
      kind: Plan
      metadata:
        name: k3s-server
        namespace: system-upgrade
        labels:
          k3s-upgrade: server
      spec:
        concurrency: 1
        version: #{new_k3s_version}
        nodeSelector:
          matchExpressions:
            - {key: node-role.kubernetes.io/master, operator: In, values: ["true"]}
        serviceAccountName: system-upgrade
        tolerations:
        - key: "CriticalAddonsOnly"
          operator: "Equal"
          value: "true"
          effect: "NoExecute"
        cordon: true
        upgrade:
          image: rancher/k3s-upgrade
    EOF
    BASH

    status, result = Util::Shell.run(command, configuration.kubeconfig_path)

    command = <<-BASH
    kubectl apply -f - <<-EOF
      apiVersion: upgrade.cattle.io/v1
      kind: Plan
      metadata:
        name: k3s-agent
        namespace: system-upgrade
        labels:
          k3s-upgrade: agent
      spec:
        concurrency: #{worker_upgrade_concurrency}
        version: #{new_k3s_version}
        nodeSelector:
          matchExpressions:
            - {key: node-role.kubernetes.io/master, operator: NotIn, values: ["true"]}
        serviceAccountName: system-upgrade
        prepare:
          image: rancher/k3s-upgrade
          args: ["prepare", "k3s-server"]
        cordon: true
        upgrade:
          image: rancher/k3s-upgrade
    EOF
    BASH

    status, result = Util::Shell.run(command, configuration.kubeconfig_path)

    puts "Upgrade will now start. Run `watch kubectl get nodes` to see the nodes being upgraded. This should take a few minutes for a small cluster."
    puts "The API server may be briefly unavailable during the upgrade of the controlplane."

    configuration_file_path = configuration.configuration_file_path
    current_configuration = File.read(configuration_file_path)
    new_configuration = current_configuration.gsub(/k3s_version: .*/, "k3s_version: #{new_k3s_version}")

    File.write(configuration_file_path, new_configuration)
  end
end
