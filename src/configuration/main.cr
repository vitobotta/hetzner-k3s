require "yaml"

require "./models/master_node_pool"
require "./models/worker_node_pool"
require "./models/datastore"
require "./models/addons"

class Configuration::Main
  include YAML::Serializable

  # The value from the config file keeps its key, but HCLOUD_TOKEN wins whenever it is set and not
  # blank, which is what lets a config be committed with a placeholder.
  @[YAML::Field(key: "hetzner_token")]
  property hetzner_token_from_config : String = ""

  def hetzner_token : String
    environment_token = ENV["HCLOUD_TOKEN"]?.try(&.strip)
    return environment_token if environment_token && !environment_token.empty?

    hetzner_token_from_config
  end

  # The variable silently outranks a token in the file, and someone who exported it for another
  # project would otherwise run against that project without noticing. Never prints either value.
  def token_precedence_notice : String?
    environment_token = ENV["HCLOUD_TOKEN"]?.try(&.strip)
    config_token = hetzner_token_from_config.strip
    return nil if environment_token.nil? || environment_token.empty? || config_token.empty?
    return nil if environment_token == config_token

    "HCLOUD_TOKEN is set and differs from hetzner_token in the configuration file, using the one from HCLOUD_TOKEN"
  end

  getter cluster_name : String
  getter kubeconfig_path : String
  getter k3s_version : String
  getter config_format_version : String?
  @api_server_hostname : String?
  getter schedule_workloads_on_masters : Bool = false
  getter masters_pool : Configuration::Models::MasterNodePool
  getter worker_node_pools : Array(Configuration::Models::WorkerNodePool) = [] of Configuration::Models::WorkerNodePool
  getter additional_pre_k3s_commands : Array(String) = [] of String
  getter additional_post_k3s_commands : Array(String) = [] of String
  getter additional_packages : Array(String) = [] of String
  getter kube_api_server_args : Array(String) = [] of String
  getter kube_scheduler_args : Array(String) = [] of String
  getter kube_controller_manager_args : Array(String) = [] of String
  getter kube_cloud_controller_manager_args : Array(String) = [] of String
  getter cluster_autoscaler_args : Array(String) = [] of String
  getter kubelet_args : Array(String) = [] of String
  getter kube_proxy_args : Array(String) = [] of String
  getter image : String = "ubuntu-24.04"
  getter autoscaling_image : String?
  getter snapshot_os : String = "default"
  getter networking : Configuration::Models::Networking = Configuration::Models::Networking.new
  getter datastore : Configuration::Models::Datastore = Configuration::Models::Datastore.new
  getter addons : Configuration::Models::Addons = Configuration::Models::Addons.new
  getter include_instance_type_in_instance_name : Bool = false
  getter protect_against_deletion : Bool = true
  getter create_load_balancer_for_the_kubernetes_api : Bool = false
  getter disable_public_interface_for_the_kubernetes_api_load_balancer : Bool = false
  # Off by default: it makes `create` reach autoscaled nodes over SSH to bring config changes to
  # nodes the autoscaler owns. See docs/Creating_a_cluster.md.
  getter synchronise_autoscaled_nodes : Bool = false
  # Off by default: `create` then removes worker nodes that the configuration no longer renders.
  getter reconcile_node_pools : Bool = false
  getter join_via_api_server_hostname : Bool = false
  getter k3s_upgrade_concurrency : Int64 = 1
  getter grow_root_partition_automatically : Bool = true

  # Trimmed, or nil when unset or blank: the masters' TLS SANs and the workers' join address
  # read the same value, so whitespace around the name in the config cannot split the
  # --tls-san argument or make the two disagree.
  def api_server_hostname : String?
    @api_server_hostname.try(&.strip).presence
  end

  def all_kubelet_args
    ["cloud-provider=external", "resolv-conf=/etc/k8s-resolv.conf"] + kubelet_args
  end

  def use_private_ip_for_the_kubernetes_api_load_balancer? : Bool
    return false unless networking.private_network.enabled

    networking.ssh.use_private_ip || disable_public_interface_for_the_kubernetes_api_load_balancer
  end

  def external_robot_node_pools : Array(Configuration::Models::WorkerNodePool)
    worker_node_pools.select do |pool|
      next false unless pool.external?

      external = pool.external
      external && external.robot?
    end
  end

  def external_robot_node_pools? : Bool
    external_robot_node_pools.any?
  end

  def robot_credentials : NamedTuple(user: String, password: String)?
    pool = external_robot_node_pools.first?
    return nil unless pool

    external = pool.external.not_nil!
    {user: external.robot_user, password: external.robot_password}
  end

  def external_worker_hostname(pool : Configuration::Models::NodePool, index : Int32) : String
    instance_type_part = include_instance_type_in_instance_name ? "#{pool.instance_type}-" : ""
    "#{cluster_name}-#{instance_type_part}pool-#{pool.name}-worker#{index}"
  end
end
