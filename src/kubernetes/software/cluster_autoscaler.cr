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
  getter autoscaling_worker_node_pools : Array(Configuration::NodePool)
  getter worker_install_script : String
  getter first_master : ::Hetzner::Instance
  getter ssh : ::Util::SSH

  def initialize(@configuration, @settings, @first_master, @ssh, @autoscaling_worker_node_pools, @worker_install_script)
  end

  def install
    log_line "Installing Cluster Autoscaler..."

    apply_manifest_from_yaml(manifest)

    log_line "...Cluster Autoscaler installed"
  end

  private def cloud_init
    ::Hetzner::Instance::Create.cloud_init(settings, settings.networking.ssh.port, settings.snapshot_os, settings.additional_packages, settings.post_create_commands, [k3s_join_script])
  end

  private def k3s_join_script
    "|\n    #{worker_install_script.gsub("\n", "\n    ")}"
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
      "--nodes=#{autoscaling.min_instances}:#{autoscaling.max_instances}:#{pool.instance_type.upcase}:#{pool.location.upcase}:#{pool.name}"
    end
  end

  private def patch_resources(resources)
    resources.map do |resource|
      resource = Kubernetes::Resources::Resource.from_yaml(resource.to_yaml)

      if resource.kind == "Deployment"
        patched_deployment(resource)
      else
        resource
      end
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
    ]

    command += node_pool_args
  end

  private def patch_autoscaler_container(autoscaler_container)
    autoscaler_container.image = "registry.k8s.io/autoscaling/cluster-autoscaler:v1.30.2"
    autoscaler_container.command = container_command

    set_container_environment_variable(autoscaler_container, "HCLOUD_CLOUD_INIT", Base64.strict_encode(cloud_init))
    set_container_environment_variable(autoscaler_container, "HCLOUD_IMAGE", settings.autoscaling_image || settings.image)
    set_container_environment_variable(autoscaler_container, "HCLOUD_FIREWALL", settings.cluster_name)
    set_container_environment_variable(autoscaler_container, "HCLOUD_SSH_KEY", settings.cluster_name)
    set_container_environment_variable(autoscaler_container, "HCLOUD_NETWORK", (settings.networking.private_network.existing_network_name.blank? ? settings.cluster_name : settings.networking.private_network.existing_network_name))
    set_container_environment_variable(autoscaler_container, "HCLOUD_PUBLIC_IPV4", settings.networking.public_network.ipv4.to_s)
    set_container_environment_variable(autoscaler_container, "HCLOUD_PUBLIC_IPV6", settings.networking.public_network.ipv6.to_s)

    set_certificate_path(autoscaler_container)
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
