require "../../configuration/loader"
require "../../configuration/main"
require "../../hetzner/instance"
require "../../hetzner/instance/create"
require "../../util"
require "../../util/shell"
require "../../util/ssh"
require "../resources/resource"
require "../resources/deployment"
require "../resources/pod/spec/toleration"
require "../resources/pod/spec/container"
require "../../util"
require "../util"
require "../script/worker_generator"

class Kubernetes::Software::ClusterAutoscaler
  include Util
  include Kubernetes::Util

  getter configuration : Configuration::Loader
  getter settings : Configuration::Main { configuration.settings }
  getter autoscaling_worker_node_pools : Array(Configuration::WorkerNodePool)
  getter first_master : ::Hetzner::Instance
  getter ssh : ::Util::SSH
  getter masters : Array(::Hetzner::Instance)

  def initialize(
    @configuration : Configuration::Loader,
    @settings : Configuration::Main,
    @masters : Array(::Hetzner::Instance),
    @first_master : ::Hetzner::Instance,
    @ssh : ::Util::SSH,
    @autoscaling_worker_node_pools : Array(Configuration::WorkerNodePool)
  )
  end

  def install : Nil
    log_line "Installing Cluster Autoscaler...", log_prefix: default_log_prefix

    apply_manifest_from_yaml(manifest, "Failed to install Cluster Autoscaler")

    log_line "...Cluster Autoscaler installed", log_prefix: default_log_prefix
  end

  private def cloud_init(pool : Configuration::WorkerNodePool) : String
    worker_install_script = ::Kubernetes::Script::WorkerGenerator.new(
      configuration, 
      settings
    ).generate_script(masters, first_master, pool)
    
    ::Hetzner::Instance::Create.cloud_init(
      settings, 
      settings.networking.ssh.port, 
      settings.snapshot_os, 
      settings.additional_packages, 
      settings.additional_pre_k3s_commands, 
      settings.additional_post_k3s_commands, 
      [worker_install_script]
    )
  end

  private def certificate_path : String
    @certificate_path ||= begin
      command = "[ -f /etc/ssl/certs/ca-certificates.crt ] && echo 1 || echo 2"
      result = ssh.run(
        first_master, 
        settings.networking.ssh.port, 
        command, 
        settings.networking.ssh.use_agent, 
        false
      ).chomp
      
      result == "1" ? "/etc/ssl/certs/ca-certificates.crt" : "/etc/ssl/certs/ca-bundle.crt"
    end
  end

  private def node_pool_args : Array(String)
    autoscaling_worker_node_pools.map do |pool|
      autoscaling = pool.autoscaling.not_nil!
      node_pool_name = build_node_pool_name(pool)
      "--nodes=#{autoscaling.min_instances}:#{autoscaling.max_instances}:#{pool.instance_type.upcase}:#{pool.location.upcase}:#{node_pool_name}"
    end
  end

  private def build_node_pool_name(pool : Configuration::WorkerNodePool) : String
    name = pool.name
    raise "Worker node pool name cannot be nil" unless name
    pool.include_cluster_name_as_prefix ? "#{settings.cluster_name}-#{name}" : name
  end

  private def autoscaler_config_args : Array(String)
    config = settings.cluster_autoscaler
    [
      "--scan-interval=#{config.scan_interval}",
      "--scale-down-delay-after-add=#{config.scale_down_delay_after_add}",
      "--scale-down-delay-after-delete=#{config.scale_down_delay_after_delete}",
      "--scale-down-delay-after-failure=#{config.scale_down_delay_after_failure}",
      "--max-node-provision-time=#{config.max_node_provision_time}",
    ]
  end

  private def patch_resources(resources : Array(YAML::Any)) : Array(YAML::Any)
    resources.map do |resource|
      parsed_resource = Kubernetes::Resources::Resource.from_yaml(resource.to_yaml)
      
      case parsed_resource.kind
      when "Deployment"
        patched_deployment = patch_deployment_resource(resource)
        YAML.parse(patched_deployment.to_yaml)
      when "ClusterRole"
        patched_cluster_role = patch_cluster_role_resource(resource)
        YAML.parse(patched_cluster_role.to_yaml)
      else
        resource
      end
    end
  end

  private def patch_deployment_resource(resource : YAML::Any) : Kubernetes::Resources::Deployment
    deployment = Kubernetes::Resources::Deployment.from_yaml(resource.to_yaml)
    patch_deployment_tolerations(deployment)
    patch_deployment_containers(deployment)
    patch_deployment_volumes(deployment)
    deployment
  end

  private def patch_cluster_role_resource(resource : YAML::Any) : Kubernetes::Resources::Resource
    cluster_role = YAML.parse(resource.to_yaml)
    add_volumeattachments_permission(cluster_role)
    Kubernetes::Resources::Resource.from_yaml(cluster_role.to_yaml)
  end

  private def add_volumeattachments_permission(cluster_role : YAML::Any) : Nil
    rules = cluster_role["rules"]?.try(&.as_a)
    return unless rules

    rules.each do |rule|
      api_groups = rule["apiGroups"]?.try(&.as_a)
      next unless api_groups
      next unless api_groups.any? { |group| group.as_s == "storage.k8s.io" }

      resources = rule["resources"]?.try(&.as_a)
      next unless resources

      has_volumeattachments = resources.any? { |r| r.as_s == "volumeattachments" }
      next if has_volumeattachments

      resources << YAML::Any.new("volumeattachments")
      log_line "Added volumeattachments permission to cluster autoscaler ClusterRole", log_prefix: default_log_prefix
    end
  end

  private def patch_deployment_tolerations(deployment : Kubernetes::Resources::Deployment) : Void
    pod_spec = deployment.spec.template.spec
    pod_spec.add_toleration(key: "CriticalAddonsOnly", value: "true", effect: "NoExecute")
  end

  private def container_command : Array(String)
    [
      "./cluster-autoscaler",
      "--cloud-provider=hetzner",
      "--enforce-node-group-min-size",
    ] + settings.cluster_autoscaler_args + node_pool_args + autoscaler_config_args
  end

  private def build_config_json : String
    image = settings.autoscaling_image || settings.image
    node_configs = build_node_configs

    config = {
      "imagesForArch" => {
        "arm64" => image,
        "amd64" => image,
      },
      "nodeConfigs" => node_configs,
    }

    config.to_json
  end

  private def build_node_configs : Hash(String, JSON::Any)
    node_configs = {} of String => JSON::Any

    autoscaling_worker_node_pools.each do |pool|
      node_pool_name = build_node_pool_name(pool)
      node_config = build_node_config(pool)
      node_configs[node_pool_name] = JSON.parse(node_config.to_json)
    end

    node_configs
  end

  private def build_node_config(pool : Configuration::WorkerNodePool) : Hash(String, JSON::Any)
    labels = extract_labels(pool)
    taints = extract_taints(pool)
    json_labels = JSON.parse(labels.to_json)
    json_taints = JSON.parse(taints.to_json)

    {
      "cloudInit" => JSON::Any.new(cloud_init(pool)),
      "labels"    => json_labels,
      "taints"    => json_taints,
    }
  end

  private def extract_labels(pool : Configuration::WorkerNodePool) : Hash(String, String)
    labels = {} of String => String
    pool.labels.each do |label|
      key = label.key
      value = label.value
      labels[key] = value if key && value
    end
    labels
  end

  private def extract_taints(pool : Configuration::WorkerNodePool) : Array(Hash(String, String))
    taints = [] of Hash(String, String)
    pool.taints.each do |taint|
      key = taint.key
      value = taint.value
      next unless key && value

      value_parts = value.split(":")
      next if value_parts.size < 2

      taints << {
        "key"    => key,
        "value"  => value_parts[0],
        "effect" => value_parts[1],
      }
    end
    taints
  end

  private def patch_autoscaler_container(container : Kubernetes::Resources::Pod::Spec::Container) : Void
    container.image = "registry.k8s.io/autoscaling/cluster-autoscaler:#{settings.manifests.cluster_autoscaler_container_image_tag}"
    container.command = container_command

    update_container_environment_variables(container)
    update_certificate_path(container)
  end

  private def update_container_environment_variables(container : Kubernetes::Resources::Pod::Spec::Container) : Void
    env_vars = container.env || [] of Kubernetes::Resources::Pod::Spec::Container::EnvVariable
    
    remove_env_variable(env_vars, "HCLOUD_CLOUD_INIT")
    set_env_variable(env_vars, "HCLOUD_CLUSTER_CONFIG", Base64.strict_encode(build_config_json))
    set_env_variable(env_vars, "HCLOUD_FIREWALL", settings.cluster_name)
    set_env_variable(env_vars, "HCLOUD_SSH_KEY", settings.cluster_name)
    set_env_variable(env_vars, "HCLOUD_NETWORK", resolve_network_name)
    set_env_variable(env_vars, "HCLOUD_PUBLIC_IPV4", settings.networking.public_network.ipv4.to_s)
    set_env_variable(env_vars, "HCLOUD_PUBLIC_IPV6", settings.networking.public_network.ipv6.to_s)
    
    container.env = env_vars
  end

  private def update_certificate_path(container : Kubernetes::Resources::Pod::Spec::Container) : Void
    volume_mounts = container.volumeMounts || [] of Kubernetes::Resources::Pod::Spec::Container::VolumeMount
    
    ssl_mount = volume_mounts.find { |mount| mount.name == "ssl-certs" }
    ssl_mount.mountPath = certificate_path if ssl_mount
    
    container.volumeMounts = volume_mounts
  end

  private def resolve_network_name : String
    existing_name = settings.networking.private_network.existing_network_name
    existing_name.blank? ? settings.cluster_name : existing_name
  end

  private def remove_env_variable(env_vars : Array(Kubernetes::Resources::Pod::Spec::Container::EnvVariable), name : String) : Void
    env_vars.reject! { |env| env.name == name }
  end

  private def set_env_variable(env_vars : Array(Kubernetes::Resources::Pod::Spec::Container::EnvVariable), name : String, value : String) : Void
    existing = env_vars.find { |env| env.name == name }
    if existing
      existing.value = value
    else
      env_vars << Kubernetes::Resources::Pod::Spec::Container::EnvVariable.new(name: name, value: value)
    end
  end

  private def patch_deployment_containers(deployment : Kubernetes::Resources::Deployment) : Void
    containers = deployment.spec.template.spec.containers
    return unless containers

    autoscaler_container = containers.find { |c| c.name == "cluster-autoscaler" }
    patch_autoscaler_container(autoscaler_container) if autoscaler_container
  end

  private def patch_deployment_volumes(deployment : Kubernetes::Resources::Deployment) : Void
    volumes = deployment.spec.template.spec.volumes
    return unless volumes

    ssl_volume = volumes.find { |v| v.name == "ssl-certs" }
    return unless ssl_volume

    host_path = ssl_volume.hostPath
    host_path.path = certificate_path if host_path
  end

  private def manifest : String
    manifest_url = settings.manifests.cluster_autoscaler_manifest_url
    raw_manifest = fetch_manifest(manifest_url)
    
    resources = YAML.parse_all(raw_manifest)
    patched_resources = patch_resources(resources)
    
    patched_resources.map(&.to_yaml).join("---\n")
  end

  private def default_log_prefix : String
    "Cluster Autoscaler"
  end
end
