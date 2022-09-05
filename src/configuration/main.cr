require "yaml"
require "crest"

require "../hetzner/client"
require "./node_pool"
require "../network"
require "../instance_group"


class Configuration::Main
  include YAML::Serializable

  property hetzner_token : String?
  property cluster_name : String?
  property kubeconfig_path : String?
  property k3s_version : String?
  property public_ssh_key_path : String?
  property private_ssh_key_path : String?
  property ssh_allowed_networks : Array(String)?
  property api_allowed_networks : Array(String)?
  property verify_host_key : Bool? = false
  property schedule_workloads_on_masters : Bool? = false
  property enable_encryption : Bool? = false
  property masters_pool : Configuration::NodePool?
  property worker_node_pools : Array(Configuration::NodePool)?
  property post_create_commands : Array(String)?
  property additional_packages : Array(String)?
  property kube_api_server_args : Array(String)?
  property kube_scheduler_args : Array(String)?
  property kube_controller_manager_args : Array(String)?
  property kube_cloud_controller_manager_args : Array(String)?
  property kubelet_args : Array(String)?
  property kube_proxy_args : Array(String)?
  property existing_network : String?

  @[YAML::Field(key: "errors", ignore: true)]
  getter errors : Array(String) = [] of String

  @[YAML::Field(key: "hetzner_client", ignore: true)]
  setter hetzner_client : Hetzner::Client | Nil

  @[YAML::Field(key: "locations", ignore: true)]
  private getter locations : Array(String) = [] of String

  @[YAML::Field(key: "server_types", ignore: true)]
  private getter server_types : Array(String) = [] of String

  @[YAML::Field(key: "server_types_loaded", ignore: true)]
  private property server_types_loaded : Bool = false

  @[YAML::Field(key: "locations_loaded", ignore: true)]
  private property locations_loaded : Bool = false

  def self.load(configuration_file_path : String)
    configuration_file_path = Path[configuration_file_path].expand(home: true).to_s

    if File.exists? configuration_file_path
      if File.directory? configuration_file_path
        puts "Configuration path points to a directory, not a file"
        exit 1
      else
        Configuration::Main.from_yaml(File.read(configuration_file_path))
      end
    else
      puts "Configuration file not found at #{configuration_file_path}"
      exit 1
    end
  rescue ex : YAML::ParseException
    puts "Error parsing configuration file: #{ex.message}"
    exit 1
  end

  def validate(command)
    puts "Validating configuration..."

    validate_hetzner_token

    print_errors

    validate_cluster_name

    case command
    when :create
      validate_kubeconfig_path(file_must_exist: false)
      validate_create
    when :delete
      validate_kubeconfig_path(file_must_exist: true)
    when :upgrade
      validate_kubeconfig_path(file_must_exist: true)
    end

    print_errors

    puts "...configuration seems valid.\n"
  end

  def hetzner_client
    @hetzner_client ||= Hetzner::Client.new(hetzner_token)
  end

  private def validate_hetzner_token
    return if valid_hetzner_token?

    errors << "Hetzner token is not valid, unable to consume to Hetzner API"
  end

  private def valid_hetzner_token?
    hetzner_client.valid_token?
  end

  private def validate_cluster_name
    if cluster_name.nil?
      errors << "cluster_name is an invalid format (only lowercase letters, digits and dashes are allowed)"
    elsif ! /\A[a-z\d-]+\z/.match cluster_name.not_nil!
      errors << "cluster_name is an invalid format (only lowercase letters, digits and dashes are allowed)"
    elsif ! /\A[a-z]+.*([a-z]|\d)+\z/.match cluster_name.not_nil!
      errors << "Ensure that the cluster_name starts and ends with a normal letter"
    end
  end

  private def validate_kubeconfig_path(file_must_exist : Bool)
    if kubeconfig_path.nil?
      errors << "kubeconfig_path is required"
    elsif File.exists?(kubeconfig_path.not_nil!) && File.directory?(kubeconfig_path.not_nil!)
      errors << "kubeconfig_path already exists and it's a directory. We would need to write a kubeconfig file at that path"
    elsif file_must_exist && ! File.exists?(kubeconfig_path.not_nil!)
      errors << "kubeconfig_path does not exist"
    end
  end

  private def validate_create
    validate_k3s_version
    validate_public_ssh_key
    validate_private_ssh_key
    validate_ssh_allowed_networks
    validate_api_allowed_networks
    validate_masters_pool
    validate_worker_node_pools
  end

  private def validate_k3s_version
    if k3s_version.nil?
      errors << "k3s_version is required"
    elsif ! ::K3s.available_releases.includes?(k3s_version.not_nil!)
      errors << "K3s version is not valid, run `hetzner-k3s releases` to see available versions"
    end
  end

  private def public_ssh_key_path
    unless @public_ssh_key_path.nil?
      Path[@public_ssh_key_path.not_nil!].expand(home: true).to_s
    end
  end

  private def private_ssh_key_path
    unless @private_ssh_key_path.nil?
      Path[@private_ssh_key_path.not_nil!].expand(home: true).to_s
    end
  end

  private def validate_public_ssh_key
    if public_ssh_key_path.nil?
      errors << "public_ssh_key_path is required"
    elsif ! File.exists?(public_ssh_key_path.not_nil!)
      errors << "public_ssh_key_path does not exist"
    elsif File.directory?(public_ssh_key_path.not_nil!)
      errors << "public_ssh_key_path is a directory, while we expect a public key file"
    end
  end

  private def validate_private_ssh_key
    if private_ssh_key_path.nil?
      errors << "private_ssh_key_path is required"
    elsif ! File.exists?(private_ssh_key_path.not_nil!)
      errors << "private_ssh_key_path does not exist"
    elsif File.directory?(private_ssh_key_path.not_nil!)
      errors << "private_ssh_key_path is a directory, while we expect a public key file"
    end
  end

  private def validate_networks(network_type : String)
    networks = case network_type
    when "SSH"
      ssh_allowed_networks
    when "API"
      api_allowed_networks
    end

    if networks.nil?
      errors << "#{network_type} allowed networks are required"
    elsif networks.empty?
      errors << "#{network_type} allowed networks are required"
    else
      networks.each do |network|
        @errors = errors + Network.new(network, network_type).validate
      end
    end
  end

  private def validate_ssh_allowed_networks
    validate_networks("SSH")
  end

  private def validate_api_allowed_networks
    validate_networks("API")
  end

  private def validate_masters_pool
    if masters_pool.nil?
      errors << "masters_pool is required"
    else
      @errors = errors + InstanceGroup.new(
        group: masters_pool,
        type: :masters,
        masters_location: masters_location,
        server_types: server_types,
        locations: locations
      ).validate
    end
  end

  private def schedule_workloads_on_masters?
    @schedule_workloads_on_masters ||= false
  end

  private def validate_worker_node_pools
    if worker_node_pools.nil?
      unless schedule_workloads_on_masters?
        errors << "worker_node_pools is required"
      end
    else
      node_pools = worker_node_pools.not_nil!

      unless node_pools.size.positive? || schedule_workloads_on_masters?
        errors << "Invalid node pools configuration"
        return
      end

      return if node_pools.size.zero? && schedule_workloads_on_masters?

      if node_pools.size.zero?
        errors << "At least one node pool is required in order to schedule workloads"
      else
        worker_node_pool_names = node_pools.map do |node_pool|
          node_pool.name
        end

        if worker_node_pool_names.uniq.size != node_pools.size
          errors << "Each node pool must have an unique name"
        end

        node_pools.map do |worker_node_pool|
          @errors = errors + InstanceGroup.new(
            group: worker_node_pool,
            type: :workers,
            masters_location: masters_location,
            server_types: server_types,
            locations: locations
          ).validate
        end
      end
    end
  end

  private def server_types : Array(String)
    return @server_types if @server_types_loaded

    server_types = hetzner_client.server_types

    if server_types.empty?
      errors << "Cannot fetch server types with Hetzner API, please try again later"
    end

    @server_types_loaded = true
    @server_types = server_types
  end

  private def locations : Array(String)
    return @locations if @locations_loaded

    locations = hetzner_client.locations

    if locations.empty?
      errors << "Cannot fetch locations with Hetzner API, please try again later"
    end

    @locations_loaded = true
    @locations = locations
  end

  private def masters_location : String | Nil
    masters_pool.try &.location
  end

  private def print_errors
    return if errors.empty?

    puts "\nSome information in the configuration file requires your attention:"

    errors.each do |error|
      STDERR.puts "  - #{error}"
    end

    exit 1
  end

  # private def validate_existing_network
  #   unless existing_network.nil?
  #     # existing_network = Hetzner::Network.new(hetzner_client: hetzner_client, cluster_name: configuration['cluster_name'], existing_network: configuration['existing_network']).get

  #   return if existing_network

  #   @errors << "You have specified that you want to use the existing network named '#{configuration['existing_network']} but this network doesn't exist"
  # end
end
