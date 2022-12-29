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


    def post_setup_deployments
      deploy_cloud_controller_manager
      deploy_csi_driver
      deploy_system_upgrade_controller
    end

    def update_nodes
      mark_nodes mark_type: :labels
      mark_nodes mark_type: :taints
    end


    def mark_nodes(mark_type:)
      check_kubectl

      action = mark_type == :labels ? 'label' : 'taint'

      if master_definitions.first[mark_type]
        master_labels = master_definitions.first[mark_type].map { |k, v| "#{k}=#{v}" }.join(' ')
        master_node_names = []

        master_definitions.each do |master|
          master_node_names << "#{configuration['cluster_name']}-#{master[:instance_type]}-#{master[:instance_id]}"
        end

        master_node_names = master_node_names.join(' ')

        cmd = "kubectl #{action} --overwrite nodes #{master_node_names} #{master_labels}"

        run cmd, kubeconfig_path: kubeconfig_path
      end

      return unless worker_definitions.any?

      worker_definitions.each do |worker|
        next unless worker[mark_type]

        worker_labels = worker[mark_type].map { |k, v| "#{k}=#{v}" }.join(' ')
        worker_node_name = "#{configuration['cluster_name']}-#{worker[:instance_type]}-#{worker[:instance_id]}"

        cmd = "kubectl #{action} --overwrite nodes #{worker_node_name} #{worker_labels}"

        run cmd, kubeconfig_path: kubeconfig_path
      end
    end

    def deploy_cloud_controller_manager
      check_kubectl

      puts
      puts 'Deploying Hetzner Cloud Controller Manager...'

      cmd = <<~BASH
        kubectl apply -f - <<-EOF
          apiVersion: "v1"
          kind: "Secret"
          metadata:
            namespace: 'kube-system'
            name: 'hcloud'
          stringData:
            network: "#{configuration['existing_network'] || cluster_name}"
            token: "#{configuration.hetzner_token}"
        EOF
      BASH

      run cmd, kubeconfig_path: kubeconfig_path

      cmd = 'kubectl apply -f https://github.com/hetznercloud/hcloud-cloud-controller-manager/releases/latest/download/ccm-networks.yaml'

      run cmd, kubeconfig_path: kubeconfig_path

      puts '...Cloud Controller Manager deployed'
    end

    def deploy_system_upgrade_controller
      check_kubectl

      puts
      puts 'Deploying k3s System Upgrade Controller...'

      cmd = 'kubectl apply -f https://github.com/rancher/system-upgrade-controller/releases/download/v0.9.1/system-upgrade-controller.yaml'

      run cmd, kubeconfig_path: kubeconfig_path

      puts '...k3s System Upgrade Controller deployed'
    end

    def deploy_csi_driver
      check_kubectl

      puts
      puts 'Deploying Hetzner CSI Driver...'

      cmd = <<~BASH
        kubectl apply -f - <<-EOF
          apiVersion: "v1"
          kind: "Secret"
          metadata:
            namespace: 'kube-system'
            name: 'hcloud-csi'
          stringData:
            token: "#{configuration.hetzner_token}"
        EOF
      BASH

      run cmd, kubeconfig_path: kubeconfig_path

      cmd = 'kubectl apply -f https://raw.githubusercontent.com/hetznercloud/csi-driver/master/deploy/kubernetes/hcloud-csi.yml'

      run cmd, kubeconfig_path: kubeconfig_path

      puts '...CSI Driver deployed'
    end

    def check_kubectl
      return if which('kubectl')

      puts 'Please ensure kubectl is installed and in your PATH.'
      exit 1
    end

  end
end
