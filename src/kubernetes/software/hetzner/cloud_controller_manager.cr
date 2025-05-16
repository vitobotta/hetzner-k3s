require "../../../util"
require "../../util"
require "yaml"

class Kubernetes::Software::Hetzner::CloudControllerManager
  include Util
  include Kubernetes::Util

  getter configuration : Configuration::Loader
  getter settings : Configuration::Main { configuration.settings }

  def initialize(@configuration, @settings)
  end

  def install
    log_line "Installing Hetzner Cloud Controller Manager..."

    apply_manifest_from_yaml(manifest, "Failed to install Hetzner Cloud Controller Manager")

    log_line "Hetzner Cloud Controller Manager installed"
  end

  private def default_log_prefix
    "Hetzner Cloud Controller"
  end

  private def manifest
    manifest_url = if settings.networking.private_network.enabled
                     settings.manifests.cloud_controller_manager_manifest_url
                   else
                     settings.manifests.cloud_controller_manager_manifest_url.gsub("-networks", "")
                   end

    manifest = fetch_manifest(manifest_url)
    manifest.gsub(/--cluster-cidr=[^"]+/, "--cluster-cidr=#{settings.networking.cluster_cidr}")

    documents = YAML.parse_all(manifest)

    if settings.responds_to?(:robot_user) && settings.robot_user
      documents.each do |doc|
        next unless doc["kind"]?.try(&.as_s) == "Deployment"
        next unless doc["metadata"]?.try(&.["name"]?.try(&.as_s)) == "hcloud-cloud-controller-manager"

        containers_any = doc["spec"]?.try(&.["template"]?.try(&.["spec"]?.try(&.["containers"]?)))
        next unless containers_any && (containers_array = containers_any.as_a?)

        container_any = containers_array[0]?
        next unless container_any && (container_hash = container_any.as_h?)

        env_array = container_hash[YAML::Any.new("env")]?.try(&.as_a) || [] of YAML::Any

        robot_enabled = YAML::Any.new({
          YAML::Any.new("name")  => YAML::Any.new("ROBOT_ENABLED"),
          YAML::Any.new("value") => YAML::Any.new("true"),
        })

        env_array << robot_enabled

        if settings.networking.private_network.enabled
          network_routes_enabled = YAML::Any.new({
            YAML::Any.new("name")  => YAML::Any.new("HCLOUD_NETWORK_ROUTES_ENABLED"),
            YAML::Any.new("value") => YAML::Any.new("false"),
          })
          env_array << network_routes_enabled
        end

        container_hash[YAML::Any.new("env")] = YAML::Any.new(env_array)

        containers_array[0] = YAML::Any.new(container_hash)
      end
    end

    documents.map(&.to_yaml).join("---\n")
  end
end
