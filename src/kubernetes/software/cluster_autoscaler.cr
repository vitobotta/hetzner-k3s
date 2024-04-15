require "../../configuration/loader"
require "../../configuration/main"
require "../../hetzner/server"
require "../../hetzner/server/create"
require "../../util"
require "../../util/shell"
require "../../util/ssh"

class Kubernetes::Software::ClusterAutoscaler
  CLUSTER_AUTOSCALER_MANIFEST = {{ read_file("#{__DIR__}/../../../templates/cluster_autoscaler.yaml") }}

  getter configuration : Configuration::Loader
  getter settings : Configuration::Main { configuration.settings }
  getter autoscaling_worker_node_pools : Array(Configuration::NodePool)
  getter worker_install_script : String
  getter first_master : ::Hetzner::Server
  getter ssh : Util::SSH

  def initialize(@configuration, @settings, @first_master, @ssh, @autoscaling_worker_node_pools, @worker_install_script)
  end

  def install
    puts "\n[Cluster Autoscaler] Installing Cluster Autoscaler..."

    node_pool_args = autoscaling_worker_node_pools.map do |pool|
      autoscaling = pool.autoscaling.not_nil!
      "- --nodes=#{autoscaling.min_instances}:#{autoscaling.max_instances}:#{pool.instance_type.upcase}:#{pool.location.upcase}:#{pool.name}"
    end.join("\n            ")

    k3s_join_script = "|\n    #{worker_install_script.gsub("\n", "\n    ")}"

    cloud_init = ::Hetzner::Server::Create.cloud_init(settings.ssh_port, settings.snapshot_os, settings.additional_packages, settings.post_create_commands, [k3s_join_script])

    certificate_path = ssh.run(first_master, settings.ssh_port, "[ -f /etc/ssl/certs/ca-certificates.crt ] && echo 1 || echo 2", settings.use_ssh_agent, false).chomp == "1" ? "/etc/ssl/certs/ca-certificates.crt" : "/etc/ssl/certs/ca-bundle.crt"

    cluster_autoscaler_manifest = Crinja.render(CLUSTER_AUTOSCALER_MANIFEST, {
      node_pool_args: node_pool_args,
      cloud_init: Base64.strict_encode(cloud_init),
      image: settings.autoscaling_image || settings.image,
      firewall_name: settings.cluster_name,
      ssh_key_name: settings.cluster_name,
      network_name: (settings.existing_network || settings.cluster_name),
      certificate_path: certificate_path
    })

    cluster_autoscaler_manifest_path = "/tmp/cluster_autoscaler_manifest_path.yaml"

    File.write(cluster_autoscaler_manifest_path, cluster_autoscaler_manifest)

    command = "kubectl apply -f #{cluster_autoscaler_manifest_path}"

    result = Util::Shell.run(command, configuration.kubeconfig_path, settings.hetzner_token, prefix: "Cluster Autoscaler")

    unless result.success?
      puts "Failed to deploy Cluster Autoscaler:"
      puts result.output
      exit 1
    end

    puts "[Cluster Autoscaler] ...Cluster Autoscaler installed"
  end
end
