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

class Kubernetes::Software::ClusterAutoscaler
  include Util
  include Kubernetes::Util

  getter configuration : Configuration::Loader
  getter settings : Configuration::Main { configuration.settings }
  getter autoscaling_worker_node_pools : Array(Configuration::WorkerNodePool)
  getter first_master : ::Hetzner::Instance
  getter ssh : ::Util::SSH
  getter masters : Array(::Hetzner::Instance)

  def initialize(@configuration, @settings, @masters, @first_master, @ssh, @autoscaling_worker_node_pools)
  end

  def install
    log_line "Installing Cluster Autoscaler..."

    apply_manifest_from_yaml(manifest)

    log_line "...Cluster Autoscaler installed"
  end

  private def cloud_init(pool)
    worker_install_script = ::Kubernetes::Installer.worker_install_script(settings, masters, first_master, pool)
    worker_install_script = "|\n    #{worker_install_script.gsub("\n", "\n    ")}"
    ::Hetzner::Instance::Create.cloud_init(settings, settings.networking.ssh.port, settings.snapshot_os, settings.additional_packages, settings.post_create_commands, [worker_install_script])
  end

  private def certificate_path
    @certificate_path ||= if ssh.run(first_master, settings.networking.ssh.port, "[ -f /etc/ssl/certs/ca-certificates.crt ] && echo 1 || echo 2", settings.networking.ssh.use_agent, false).chomp == "1"
      "/etc/ssl/certs/ca-certificates.crt"
    else
      "/etc/ssl/certs/ca-bundle.crt"
    end
  end

  private def node_pool_args
    autoscaling_worker_node_pools.map do |pool|
      autoscaling = pool.autoscaling.not_nil!
      node_pool_name = pool.include_cluster_name_as_prefix ? "#{settings.cluster_name}-#{pool.name}" : pool.name
      "--nodes=#{autoscaling.min_instances}:#{autoscaling.max_instances}:#{pool.instance_type.upcase}:#{pool.location.upcase}:#{node_pool_name}"
    end
  end

  private def patch_resources(resources)
    resources.map do |resource|
      resource = Kubernetes::Resources::Resource.from_yaml(resource.to_yaml)
      resource.kind == "Deployment" ? patched_deployment(resource) : resource
    end
  end

  private def patched_deployment(resource)
    deployment = Kubernetes::Resources::Deployment.from_yaml(resource.to_yaml)

    patch_tolerations(deployment.spec.template.spec)
    patch_containers(deployment.spec.template.spec.containers)
    patch_volumes(deployment.spec.template.spec.volumes)

    deployment
  end

  private def patch_tolerations(pod_spec)
    pod_spec.add_toleration(key: "CriticalAddonsOnly", value: "true", effect: "NoExecute")
  end

  private def container_command
    command = [
      "./cluster-autoscaler",
      "--cloud-provider=hetzner",
      "--enforce-node-group-min-size",
      "--v=4"
    ]

    command += node_pool_args
  end

  private def build_config_json
    image = settings.autoscaling_image || settings.image

    node_configs = {} of String => JSON::Any

    autoscaling_worker_node_pools.each do |pool|
      node_pool_name = pool.include_cluster_name_as_prefix ? "#{settings.cluster_name}-#{pool.name}" : pool.name
      next if node_pool_name.nil?

      node_config = {
        "cloudInit" => cloud_init(pool)
      }

      node_configs[node_pool_name] = JSON.parse(node_config.to_json)
    end

    config = {
      "imagesForArch" => {
        "arm64" => image,
        "amd64" => image
      },
      "nodeConfigs" => node_configs
    }

    config.to_json
  end

  private def patch_autoscaler_container(autoscaler_container)
    autoscaler_container.image = "registry.k8s.io/autoscaling/cluster-autoscaler:#{settings.manifests.cluster_autoscaler_container_image_tag}"
    autoscaler_container.command = container_command

    remove_container_environment_variable(autoscaler_container, "HCLOUD_CLOUD_INIT")

    set_container_environment_variable(autoscaler_container, "HCLOUD_CLUSTER_CONFIG", Base64.strict_encode(build_config_json))
    set_container_environment_variable(autoscaler_container, "HCLOUD_FIREWALL", settings.cluster_name)
    set_container_environment_variable(autoscaler_container, "HCLOUD_SSH_KEY", settings.cluster_name)
    set_container_environment_variable(autoscaler_container, "HCLOUD_NETWORK", (settings.networking.private_network.existing_network_name.blank? ? settings.cluster_name : settings.networking.private_network.existing_network_name))
    set_container_environment_variable(autoscaler_container, "HCLOUD_PUBLIC_IPV4", settings.networking.public_network.ipv4.to_s)
    set_container_environment_variable(autoscaler_container, "HCLOUD_PUBLIC_IPV6", settings.networking.public_network.ipv6.to_s)

    set_certificate_path(autoscaler_container)
  end

  private def remove_container_environment_variable(autoscaler_container, variable_name)
    env_variables = autoscaler_container.env

    return if env_variables.nil?

    env_variables.reject! { |env| env.name == variable_name }
  end

  private def set_container_environment_variable(autoscaler_container, variable_name, variable_value)
    env_variables = autoscaler_container.env

    return if env_variables.nil?

    if variable = env_variables.find { |env| env.name == variable_name }
      variable.value = variable_value
    else
      env_variables << Kubernetes::Resources::Pod::Spec::Container::EnvVariable.new(name: variable_name, value: variable_value)
    end
  end

  private def set_certificate_path(autoscaler_container)
    volume_mounts = autoscaler_container.volumeMounts

    return unless volume_mounts

    if volume_mount = volume_mounts.find { |volume_mount| volume_mount.name == "ssl-certs" }
      volume_mount.mountPath = certificate_path
    end
  end

  private def patch_containers(containers)
    return unless containers

    if autoscaler_container = containers.find { |container| container.name == "cluster-autoscaler" }
      patch_autoscaler_container(autoscaler_container)
    end
  end

  private def patch_volumes(volumes)
    return unless volumes

    certificate_volume = volumes.find { |volume| volume.name == "ssl-certs" }

    return unless certificate_volume

    if host_path = certificate_volume.hostPath
      host_path.path = certificate_path
    end
  end

  private def manifest
    manifest = fetch_manifest(settings.manifests.cluster_autoscaler_manifest_url)
    resources = YAML.parse_all(manifest)
    patched_resources = patch_resources(resources)
    patched_resources.map(&.to_yaml).join
  end

  private def default_log_prefix
    "Cluster Autoscaler"
  end
end
