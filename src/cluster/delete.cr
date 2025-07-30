require "../configuration/loader"
require "../hetzner/ssh_key/delete"
require "../hetzner/firewall/delete"
require "../hetzner/network/delete"
require "../hetzner/instance/delete"
require "../hetzner/load_balancer/delete"
require "../kubernetes/util"
require "../util/shell"
require "../util"

class Cluster::Delete
  include Util
  include Util::Shell
  include Kubernetes::Util

  private getter configuration : Configuration::Loader
  private getter hetzner_client : Hetzner::Client do
    configuration.hetzner_client
  end
  private getter settings : Configuration::Main do
    configuration.settings
  end
  private getter force : Bool = false
  private property instance_deletors : Array(Hetzner::Instance::Delete) = [] of Hetzner::Instance::Delete

  def initialize(@configuration, @force)
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

    delete_instances
    delete_network if settings.networking.private_network.enabled
    delete_firewall if settings.networking.private_network.enabled || !settings.networking.public_network.use_local_firewall
    delete_ssh_key
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

    channel = Channel(String).new

    instance_deletors.each do |instance_deletor|
      spawn do
        instance_deletor.run
        channel.send(instance_deletor.instance_name)
      end
    end

    instance_deletors.size.times do
      channel.receive
    end
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
      ssh_key_name: settings.cluster_name,
      public_ssh_key_path: settings.networking.ssh.public_key_path
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
    no_autoscaling_worker_node_pools = settings.worker_node_pools.reject(&.autoscaling_enabled)

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
    result = run_shell_command("kubectl get nodes -o=custom-columns=NAME:.metadata.name --request-timeout=10s 2>/dev/null", configuration.kubeconfig_path, settings.hetzner_token, abort_on_error: false, print_output: false)
    return detect_nodes_with_hetzner_api unless result.success?

    lines = result.output.split("\n")
    lines = lines[1..] if lines.size > 1 && lines[0].includes?("NAME")
    all_node_names = lines.reject(&.empty?)

    all_node_names.each { |node_name| add_instance_deletor(node_name) unless instance_deletor_exists?(node_name) }
    detect_nodes_with_hetzner_api if all_node_names.empty?
  end

  private def add_instance_deletor(instance_name)
    instance_deletors << Hetzner::Instance::Delete.new(settings: settings, hetzner_client: hetzner_client, instance_name: instance_name)
  end

  private def detect_nodes_with_hetzner_api
    find_instances_to_delete_by_label("cluster=#{settings.cluster_name}")

    settings.worker_node_pools.each do |pool|
      next unless pool.autoscaling_enabled

      node_group_name = pool.include_cluster_name_as_prefix ? "#{settings.cluster_name}-#{pool.name}" : pool.name
      find_instances_to_delete_by_label("hcloud/node-group=#{node_group_name}")
    end
  end

  private def find_instances_to_delete_by_label(label_selector)
    success, response = hetzner_client.get("/servers", {:label_selector => label_selector})
    return unless success

    JSON.parse(response)["servers"].as_a.each do |instance_data|
      instance_name = instance_data["name"].as_s
      add_instance_deletor(instance_name) unless instance_deletor_exists?(instance_name)
    end
  end
end
