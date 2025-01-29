require "../configuration/loader"
require "../hetzner/placement_group/delete"
require "../hetzner/ssh_key/delete"
require "../hetzner/firewall/delete"
require "../hetzner/network/delete"
require "../hetzner/instance/delete"
require "../hetzner/load_balancer/delete"
require "../hetzner/placement_group/all"
require "../util/shell"
require "../util"

class Cluster::Delete
  include Util
  include Util::Shell

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
    unless force
      print "Please enter the cluster name to confirm that you want to delete it: "
      input = gets

      if input.try(&.strip) != settings.cluster_name
        puts
        puts "Cluster name '#{input.try(&.strip)}' does not match expected '#{settings.cluster_name}'. Aborting deletion.".colorize(:red)
        puts
        exit 1
      end

      if settings.protect_against_deletion
        puts
        puts "WARNING: Cluster cannot be deleted. If you are sure about this, disable the protection by setting `protect_against_deletion` to `false` in the config file. Aborting deletion.".colorize(:red)
        puts
        exit 1
      end
    end

    delete_resources
    File.delete(settings.kubeconfig_path) if File.exists?(settings.kubeconfig_path)
  end

  private def delete_resources
    if settings.create_load_balancer_for_the_kubernetes_api
      delete_load_balancer
      sleep 5.seconds
    end

    delete_instances
    delete_placement_groups
    delete_network
    delete_firewall
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

  private def delete_placement_groups
    Hetzner::PlacementGroup::All.new(hetzner_client).delete_all
  end

  private def default_log_prefix
    "Cluster cleanup"
  end

  private def detect_nodes_with_kubectl
    result = run_shell_command("kubectl get nodes -o=custom-columns=NAME:.metadata.name | tail -n +2", configuration.kubeconfig_path, settings.hetzner_token, abort_on_error: false, print_output: false)
    all_node_names = result.output.split("\n")

    all_node_names.each do |node_name|
      unless instance_deletors.find { |deletor| deletor.instance_name == node_name }
        instance_deletors << Hetzner::Instance::Delete.new(
          settings: settings,
          hetzner_client: hetzner_client,
          instance_name: node_name
        )
      end
    end
  end
end
