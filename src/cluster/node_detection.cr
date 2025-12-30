require "../kubernetes/util"
require "../util"
require "../util/shell"

module Cluster
  module NodeDetection
    include Util
    include Util::Shell
    include Kubernetes::Util

    protected getter configuration : Configuration::Loader
    protected getter hetzner_client : Hetzner::Client do
      configuration.hetzner_client
    end
    protected getter settings : Configuration::Main do
      configuration.settings
    end

    def initialize(@configuration)
    end

    protected def detect_instances_node_names_only
      instances = detect_instances_with_kubectl_node_names_only
      return instances unless instances.empty?

      detect_instances_with_hetzner_api_node_names_only
    end

    protected def detect_instances_with_ips
      instances = detect_instances_with_kubectl_with_ips
      return instances unless instances.empty?

      detect_instances_with_hetzner_api_with_ips
    end

    private def detect_instances_with_kubectl_node_names_only
      result = run_shell_command("kubectl get nodes -o=custom-columns=NAME:.metadata.name --request-timeout=10s 2>/dev/null", configuration.kubeconfig_path, settings.hetzner_token, abort_on_error: false, print_output: false)
      return [] of String unless result.success?

      lines = result.output.split("\n")
      lines = lines[1..] if lines.size > 1 && lines[0].includes?("NAME")
      lines.reject(&.empty?)
    end

    private def detect_instances_with_kubectl_with_ips
      instances = [] of Hetzner::Instance

      result = run_shell_command("kubectl get nodes --no-headers -o custom-columns=NAME:.metadata.name --request-timeout=10s 2>/dev/null", configuration.kubeconfig_path, settings.hetzner_token, abort_on_error: false, print_output: false)
      return instances unless result.success?

      node_names = result.output.split("\n").reject(&.empty?)

      node_names.each do |node_name|
        addresses_result = run_shell_command("kubectl get node #{node_name} -o json --request-timeout=10s 2>/dev/null", configuration.kubeconfig_path, settings.hetzner_token, abort_on_error: false, print_output: false)

        if addresses_result.success? && !addresses_result.output.blank?
          begin
            node_json = JSON.parse(addresses_result.output)
            addresses = node_json["status"]["addresses"].as_a

            internal_ip = ""
            external_ip = ""

            addresses.each do |address|
              addr_type = address["type"].as_s
              addr_value = address["address"].as_s

              case addr_type
              when "InternalIP"
                internal_ip = addr_value
              when "ExternalIP"
                external_ip = addr_value
              end
            end

            if !internal_ip.blank? || !external_ip.blank?
              instances << Hetzner::Instance.new(0, "running", node_name, internal_ip, external_ip)
            end
          rescue ex
            puts "Warning: Failed to parse node data for #{node_name}: #{ex.message}".colorize(:yellow)
          end
        end
      end

      instances
    end

    private def detect_instances_with_hetzner_api_node_names_only
      instance_names = [] of String

      find_instance_names_by_label("cluster=#{settings.cluster_name}", instance_names)

      settings.worker_node_pools.each do |pool|
        next unless pool.autoscaling_enabled

        node_group_name = pool.include_cluster_name_as_prefix ? "#{settings.cluster_name}-#{pool.name}" : pool.name
        find_instance_names_by_label("hcloud/node-group=#{node_group_name}", instance_names)
      end

      instance_names
    end

    private def detect_instances_with_hetzner_api_with_ips
      instances = [] of Hetzner::Instance

      find_instances_by_label("cluster=#{settings.cluster_name}", instances)

      settings.worker_node_pools.each do |pool|
        next unless pool.autoscaling_enabled

        node_group_name = pool.include_cluster_name_as_prefix ? "#{settings.cluster_name}-#{pool.name}" : pool.name
        find_instances_by_label("hcloud/node-group=#{node_group_name}", instances)
      end

      instances
    end

    private def find_instance_names_by_label(label_selector, instance_names)
      success, response = hetzner_client.get("/servers", {:label_selector => label_selector})
      return unless success

      JSON.parse(response)["servers"].as_a.each do |instance_data|
        instance_name = instance_data["name"].as_s
        instance_names << instance_name unless instance_names.includes?(instance_name)
      end
    end

    private def find_instances_by_label(label_selector, instances)
      success, response = hetzner_client.get("/servers", {:label_selector => label_selector})
      return unless success

      JSON.parse(response)["servers"].as_a.each do |instance_data|
        instance_name = instance_data["name"].as_s
        instance_status = instance_data["status"].as_s
        instance_id = instance_data["id"].as_i

        internal_ip = ""
        external_ip = ""

        if pub_net = instance_data["public_net"]?
          if ipv4 = pub_net["ipv4"]?
            external_ip = ipv4["ip"].as_s
          end
        end

        if private_net = instance_data["private_net"]?
          if private_net.as_a.size > 0
            internal_ip = private_net.as_a[0]["ip"].as_s
          end
        end

        instances << Hetzner::Instance.new(instance_id, instance_status, instance_name, internal_ip, external_ip)
      end
    end
  end
end