require "../../configuration/loader"
require "../../configuration/main"
require "../../hetzner/instance"
require "../../hetzner/instance/create"
require "../../util"
require "../../util/shell"
require "../../util/ssh"
require "../resources/deployment"
require "../resources/pod/spec/toleration"
require "../resources/pod/spec/container"
require "../util"
require "../script/worker_generator"

class Kubernetes::Software::ClusterAutoscaler
  include Util
  include Kubernetes::Util

  CLUSTER_AUTOSCALER_NAME = "cluster-autoscaler"
  SSL_CERTS_VOLUME_NAME   = "ssl-certs"
  DEFAULT_CA_CERTIFICATES = "/etc/ssl/certs/ca-certificates.crt"
  FALLBACK_CA_BUNDLE      = "/etc/ssl/certs/ca-bundle.crt"

  CLOUD_PROVIDER                      = "hetzner"
  CRITICAL_ADDONS_ONLY_TOLERATION_KEY = "CriticalAddonsOnly"
  STORAGE_API_GROUP                   = "storage.k8s.io"
  VOLUME_ATTACHMENTS_RESOURCE         = "volumeattachments"
  HCLOUD_CLOUD_INIT_VAR               = "HCLOUD_CLOUD_INIT"
  HCLOUD_CLUSTER_CONFIG_VAR           = "HCLOUD_CLUSTER_CONFIG"
  HCLOUD_FIREWALL_VAR                 = "HCLOUD_FIREWALL"
  HCLOUD_SSH_KEY_VAR                  = "HCLOUD_SSH_KEY"
  HCLOUD_NETWORK_VAR                  = "HCLOUD_NETWORK"
  HCLOUD_PUBLIC_IPV4_VAR              = "HCLOUD_PUBLIC_IPV4"
  HCLOUD_PUBLIC_IPV6_VAR              = "HCLOUD_PUBLIC_IPV6"
  CERT_CHECK_COMMAND                  = "[ -f /etc/ssl/certs/ca-certificates.crt ] && echo 1 || echo 2"

  getter configuration : Configuration::Loader
  getter settings : Configuration::Main { configuration.settings }
  getter autoscaling_worker_node_pools : Array(Configuration::Models::WorkerNodePool)
  getter first_master : ::Hetzner::Instance
  getter ssh : ::Util::SSH
  getter masters : Array(::Hetzner::Instance)

  def initialize(
    @configuration : Configuration::Loader,
    @settings : Configuration::Main,
    @masters : Array(::Hetzner::Instance),
    @first_master : ::Hetzner::Instance,
    @ssh : ::Util::SSH,
    @autoscaling_worker_node_pools : Array(Configuration::Models::WorkerNodePool)
  )
  end

  def install : Nil
    log_line "Installing Cluster Autoscaler...", log_prefix: default_log_prefix

    apply_manifest_from_yaml(manifest, "Failed to install Cluster Autoscaler")

    log_line "...Cluster Autoscaler installed", log_prefix: default_log_prefix
  end

  private def cloud_init(pool : Configuration::Models::WorkerNodePool) : String
    worker_install_script = ::Kubernetes::Script::WorkerGenerator.new(
      configuration,
      settings
    ).generate_script(masters, first_master, pool)

    grow_root_partition_automatically = pool.effective_grow_root_partition_automatically(settings.grow_root_partition_automatically)

    ::Hetzner::Instance::Create.cloud_init(
      settings,
      grow_root_partition_automatically,
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
      command = CERT_CHECK_COMMAND
      result = ssh.run(
        first_master,
        settings.networking.ssh.port,
        command,
        settings.networking.ssh.use_agent,
        false
      ).chomp

      result == "1" ? DEFAULT_CA_CERTIFICATES : FALLBACK_CA_BUNDLE
    end
  end

  private def node_pool_args : Array(String)
    autoscaling_worker_node_pools.map do |pool|
      autoscaling = pool.autoscaling.not_nil!
      node_pool_name = build_node_pool_name(pool)
      "--nodes=#{autoscaling.min_instances}:#{autoscaling.max_instances}:#{pool.instance_type.upcase}:#{pool.location.upcase}:#{node_pool_name}"
    end
  end

  private def build_node_pool_name(pool : Configuration::Models::WorkerNodePool) : String
    name = pool.name
    raise "Worker node pool name cannot be nil" unless name
    pool.include_cluster_name_as_prefix ? "#{settings.cluster_name}-#{name}" : name
  end

  private def autoscaler_config_args : Array(String)
    config = settings.addons.cluster_autoscaler
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
      kind = resource["kind"].as_s

      case kind
      when "Deployment"
        patch_deployment(resource)
      when "ClusterRole"
        patch_cluster_role(resource)
      else
        resource
      end
    end
  end

  private def patch_deployment(resource : YAML::Any) : YAML::Any
    deployment = Kubernetes::Resources::Deployment.from_yaml(resource.to_yaml)
    patch_deployment_tolerations(deployment)
    patch_deployment_containers(deployment)
    patch_deployment_volumes(deployment)
    YAML.parse(deployment.to_yaml)
  end

  private def patch_cluster_role(resource : YAML::Any) : YAML::Any
    cluster_role = YAML.parse(resource.to_yaml)
    add_volumeattachments_permission(cluster_role)
    cluster_role
  end

  private def add_volumeattachments_permission(cluster_role : YAML::Any) : Nil
    rules = cluster_role["rules"]?.try(&.as_a)
    return unless rules

    rules.each do |rule|
      api_groups = rule["apiGroups"]?.try(&.as_a)
      next unless api_groups
      next unless api_groups.any? { |group| group.as_s == STORAGE_API_GROUP }

      resources = rule["resources"]?.try(&.as_a)
      next unless resources

      has_volumeattachments = resources.any? { |r| r.as_s == VOLUME_ATTACHMENTS_RESOURCE }
      next if has_volumeattachments

      resources << YAML::Any.new(VOLUME_ATTACHMENTS_RESOURCE)
      log_line "Added volumeattachments permission to cluster autoscaler ClusterRole", log_prefix: default_log_prefix
    end
  end

  private def patch_deployment_tolerations(deployment : Kubernetes::Resources::Deployment) : Void
    pod_spec = deployment.spec.template.spec
    pod_spec.add_toleration(key: CRITICAL_ADDONS_ONLY_TOLERATION_KEY, value: "true", effect: "NoExecute")
  end

  private def container_command : Array(String)
    [
      "./cluster-autoscaler",
      "--cloud-provider=#{CLOUD_PROVIDER}",
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

  private def build_node_config(pool : Configuration::Models::WorkerNodePool) : Hash(String, JSON::Any)
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

  private def extract_labels(pool : Configuration::Models::WorkerNodePool) : Hash(String, String)
    labels = {} of String => String
    pool.labels.each do |label|
      key = label.key
      value = label.value
      labels[key] = value if key && value
    end
    labels
  end

  private def extract_taints(pool : Configuration::Models::WorkerNodePool) : Array(Hash(String, String))
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
    container.image = "registry.k8s.io/autoscaling/cluster-autoscaler:#{settings.addons.cluster_autoscaler.container_image_tag}"
    container.command = container_command

    configure_container_environment(container)
    configure_container_volume_mounts(container)
  end

  private def configure_container_environment(container : Kubernetes::Resources::Pod::Spec::Container) : Void
    env_vars = container.env || [] of Kubernetes::Resources::Pod::Spec::Container::EnvVariable

    remove_env_variable(env_vars, HCLOUD_CLOUD_INIT_VAR)

    set_env_variable(env_vars, HCLOUD_CLUSTER_CONFIG_VAR, Base64.strict_encode(build_config_json))
    set_env_variable(env_vars, HCLOUD_FIREWALL_VAR, settings.cluster_name)
    set_env_variable(env_vars, HCLOUD_SSH_KEY_VAR, settings.cluster_name)
    set_env_variable(env_vars, HCLOUD_NETWORK_VAR, resolve_network_name)
    set_env_variable(env_vars, HCLOUD_PUBLIC_IPV4_VAR, settings.networking.public_network.ipv4.to_s)
    set_env_variable(env_vars, HCLOUD_PUBLIC_IPV6_VAR, settings.networking.public_network.ipv6.to_s)

    container.env = env_vars
  end

  private def configure_container_volume_mounts(container : Kubernetes::Resources::Pod::Spec::Container) : Void
    volume_mounts = container.volumeMounts || [] of Kubernetes::Resources::Pod::Spec::Container::VolumeMount

    ssl_mount = volume_mounts.find { |mount| mount.name == SSL_CERTS_VOLUME_NAME }
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

    autoscaler_container = containers.find { |c| c.name == CLUSTER_AUTOSCALER_NAME }
    patch_autoscaler_container(autoscaler_container) if autoscaler_container
  end

  private def patch_deployment_volumes(deployment : Kubernetes::Resources::Deployment) : Void
    volumes = deployment.spec.template.spec.volumes
    return unless volumes

    ssl_volume = volumes.find { |v| v.name == SSL_CERTS_VOLUME_NAME }
    return unless ssl_volume

    host_path = ssl_volume.hostPath
    host_path.path = certificate_path if host_path
  end

  private def manifest : String
    manifest_url = settings.addons.cluster_autoscaler.manifest_url
    raw_manifest = fetch_manifest(manifest_url)

    resources = YAML.parse_all(raw_manifest)
    patched_resources = patch_resources(resources)

    patched_resources.map(&.to_yaml).join("---\n")
  end

  private def default_log_prefix : String
    "Cluster Autoscaler"
  end
end
