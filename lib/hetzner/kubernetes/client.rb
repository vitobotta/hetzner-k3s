# frozen_string_literal: true

require_relative '../utils'

module Kubernetes
  class Client


    def deploy(masters:, workers:, master_definitions:, worker_definitions:)


      set_up_k3s

      update_nodes

      post_setup_deployments
    end

    def upgrade
      worker_upgrade_concurrency = workers.size - 1
      worker_upgrade_concurrency = 1 if worker_upgrade_concurrency.zero?

      cmd = <<~BASH
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

      run cmd, kubeconfig_path: kubeconfig_path

      cmd = <<~BASH
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

      run cmd, kubeconfig_path: kubeconfig_path

      puts 'Upgrade will now start. Run `watch kubectl get nodes` to see the nodes being upgraded. This should take a few minutes for a small cluster.'
      puts 'The API server may be briefly unavailable during the upgrade of the controlplane.'

      updated_configuration = configuration.raw
      updated_configuration['k3s_version'] = new_k3s_version

      File.write(config_file, updated_configuration.to_yaml)
    end















  end
end
