require "../configuration/loader"
require "../hetzner/ssh_key/delete"
require "../hetzner/firewall/delete"
require "../hetzner/network/delete"
require "../hetzner/instance/delete"
require "../hetzner/load_balancer/delete"
require "../hetzner/placement_group/delete"
require "./placement_group_manager"
require "../kubernetes/util"
require "../util/shell"
require "../util"
require "../util/ssh"
require "./node_detection"

class Cluster::Delete
  include Util
  include Util::Shell
  include Kubernetes::Util
  include NodeDetection

  private getter force : Bool = false
  private property instance_deletors : Array(Hetzner::Instance::Delete) = [] of Hetzner::Instance::Delete

  private getter placement_group_manager : PlacementGroupManager do
    PlacementGroupManager.new(settings, hetzner_client)
  end

  def initialize(@configuration, @force)
    super(@configuration)
  end

  def run
    return delete_resources if force

    input = get_cluster_name_input
    validate_cluster_name(input)

    if settings.protect_against_deletion
      puts "\nWARNING: Cluster cannot be deleted. If you are sure about this, disable the protection by setting `protect_against_deletion` to `false` in the config file. Aborting deletion.".colorize(:red)
      exit 1
    end

    delete_resources
    File.delete(settings.kubeconfig_path) if File.exists?(settings.kubeconfig_path)
  end

  private def get_cluster_name_input
    loop do
      print "Please enter the cluster name to confirm that you want to delete it: "
      input = gets.try(&.strip)

      return input unless input.nil? || input.empty?
      puts "\nError: Input cannot be empty. Please enter the cluster name.".colorize(:red)
    end
  end

  private def validate_cluster_name(input)
    return if input == settings.cluster_name
    puts "\nCluster name '#{input}' does not match expected '#{settings.cluster_name}'. Aborting deletion.".colorize(:red)
    exit 1
  end

  private def delete_resources
    delete_load_balancer if settings.create_load_balancer_for_the_kubernetes_api

    switch_to_context("#{settings.cluster_name}-master1", abort_on_error: false, request_timeout: 10, print_output: false)

    cleanup_external_nodes
    delete_instances
    delete_placement_groups
    delete_network if settings.networking.private_network.enabled
    delete_firewall if settings.networking.private_network.enabled || !settings.networking.public_network.use_local_firewall
    delete_ssh_key
  end

  private def cleanup_external_nodes
    external_pools = settings.worker_node_pools.select(&.external?)
    return if external_pools.empty?

    external_pools.each do |pool|
      pool.external.not_nil!.nodes.each do |node|
        cleanup_external_node(node)
      end
    end
  end

  private def cleanup_external_node(node)
    ssh = Util::SSH.new(node.ssh_private_key_path, "", false, node.ssh_user)
    instance = Hetzner::Instance.new(0, "running", node.host, node.host, node.host)
    use_sudo = node.ssh_user != "root"

    begin
      # 1. Uninstall k3s
      ssh.run(instance, node.ssh_port, "#{sudo_prefix(use_sudo)}bash -c '/usr/local/bin/k3s-agent-uninstall.sh 2>/dev/null || /usr/local/bin/k3s-uninstall.sh 2>/dev/null || true'", false, print_output: false)

      # 2. Remove firewall and reset packet filtering so the node is left open.
      ssh.run(instance, node.ssh_port, firewall_cleanup_command(use_sudo), false, print_output: false)

      log_line "Cleaned up external node #{node.host}"
    rescue ex
      log_line "Warning: Failed to clean up external node #{node.host}: #{ex.message}"
    end
  end

  private def sudo_prefix(use_sudo : Bool) : String
    use_sudo ? "sudo " : ""
  end

  private def firewall_cleanup_command(use_sudo : Bool) : String
    inner_script = <<-SCRIPT
      set +e

      systemctl stop firewall.service 2>/dev/null || true
      systemctl disable firewall.service 2>/dev/null || true

      reset_packet_filter() {
        local command="$1"

        if ! command -v "$command" >/dev/null 2>&1; then
          return 0
        fi

        "$command" -w -P INPUT ACCEPT 2>/dev/null || true
        "$command" -w -P FORWARD ACCEPT 2>/dev/null || true
        "$command" -w -P OUTPUT ACCEPT 2>/dev/null || true

        for table in filter nat mangle raw security; do
          "$command" -w -t "$table" -F 2>/dev/null || true
          "$command" -w -t "$table" -X 2>/dev/null || true
        done
      }

      reset_packet_filter iptables
      reset_packet_filter ip6tables

      if command -v ipset >/dev/null 2>&1; then
        for set_name in nodes nodes_temp allowed_networks_ssh allowed_networks_ssh_temp allowed_networks_k8s_api allowed_networks_k8s_api_temp external_nodes external_nodes_temp; do
          ipset destroy "$set_name" 2>/dev/null || true
        done
      fi

      rm -f /usr/local/bin/firewall.sh /etc/systemd/system/firewall.service /usr/local/bin/firewall-status
      rm -f /etc/allowed-networks-ssh.conf /etc/allowed-networks-kubernetes-api.conf
      rm -f /etc/iptables/rules.v4 /etc/iptables/rules.v6 /etc/iptables/ipsets.v4 /etc/iptables/ipsets.v6 2>/dev/null || true
      rm -f /tmp/last_node_ips.txt 2>/dev/null || true
      systemctl daemon-reload 2>/dev/null || true
    SCRIPT

    "#{sudo_prefix(use_sudo)}bash -c '#{inner_script.gsub("'", "'\\''")}'"
  end

  private def delete_load_balancer
    Hetzner::LoadBalancer::Delete.new(
      hetzner_client: hetzner_client,
      cluster_name: settings.cluster_name,
      print_log: true
    ).run
  end

  private def delete_instances
    initialize_masters
    initialize_worker_nodes
    detect_nodes_with_kubectl

    channel = Channel(String | Exception).new

    instance_deletors.each do |instance_deletor|
      spawn do
        begin
          instance_deletor.run
          channel.send(instance_deletor.instance_name)
        rescue e : Exception
          channel.send(e)
        end
      end
    end

    errors = [] of Exception
    instance_deletors.size.times do
      result = channel.receive
      errors << result if result.is_a?(Exception)
    end

    unless errors.empty?
      errors.each { |e| puts "Error deleting instance: #{e.message}".colorize(:red) }
    end
  end

  private def delete_placement_groups
    placement_group_manager.delete
  end

  private def delete_network
    Hetzner::Network::Delete.new(
      hetzner_client: hetzner_client,
      network_name: settings.cluster_name
    ).run
  end

  private def delete_firewall
    Hetzner::Firewall::Delete.new(
      hetzner_client: hetzner_client,
      firewall_name: settings.cluster_name
    ).run
  end

  private def delete_ssh_key
    Hetzner::SSHKey::Delete.new(
      hetzner_client: hetzner_client,
      ssh_key_name: settings.networking.ssh.ssh_key_name(settings.cluster_name),
      public_ssh_key_path: settings.networking.ssh.public_key_path,
      using_existing_ssh_key: settings.networking.ssh.using_existing_ssh_key?
    ).run
  end

  private def create_instance_deleter(instance_name)
    Hetzner::Instance::Delete.new(
      settings: settings,
      hetzner_client: hetzner_client,
      instance_name: instance_name
    )
  end

  private def instance_type_suffix(pool)
    settings.include_instance_type_in_instance_name ? "#{pool.instance_type}-" : ""
  end

  private def initialize_masters
    settings.masters_pool.instance_count.times do |i|
      instance_deletors << create_instance_deleter(
        "#{settings.cluster_name}-#{instance_type_suffix(settings.masters_pool)}master#{i + 1}"
      )
    end
  end

  private def initialize_worker_nodes
    no_autoscaling_worker_node_pools = settings.worker_node_pools.reject(&.autoscaling_enabled).reject(&.external?)

    no_autoscaling_worker_node_pools.each do |node_pool|
      node_pool.instance_count.times do |i|
        instance_deletors << create_instance_deleter(
          "#{settings.cluster_name}-#{instance_type_suffix(node_pool)}pool-#{node_pool.name}-worker#{i + 1}"
        )
      end
    end
  end

  private def default_log_prefix
    "Cluster cleanup"
  end

  private def instance_deletor_exists?(instance_name)
    instance_deletors.any? { |deletor| deletor.instance_name == instance_name }
  end

  private def detect_nodes_with_kubectl
    node_names = detect_instances_node_names_only
    node_names.each { |node_name| add_instance_deletor(node_name) unless instance_deletor_exists?(node_name) }
    detect_nodes_with_hetzner_api if node_names.empty?
  end

  private def add_instance_deletor(instance_name)
    instance_deletors << Hetzner::Instance::Delete.new(settings: settings, hetzner_client: hetzner_client, instance_name: instance_name)
  end

  private def detect_nodes_with_hetzner_api
    instance_names = [] of String
    find_instance_names_by_label("cluster=#{settings.cluster_name}", instance_names)

    settings.worker_node_pools.each do |pool|
      next unless pool.autoscaling_enabled

      node_group_name = pool.include_cluster_name_as_prefix ? "#{settings.cluster_name}-#{pool.name}" : pool.name
      find_instance_names_by_label("hcloud/node-group=#{node_group_name}", instance_names)
    end

    instance_names.each { |instance_name| add_instance_deletor(instance_name) unless instance_deletor_exists?(instance_name) }
  end
end
