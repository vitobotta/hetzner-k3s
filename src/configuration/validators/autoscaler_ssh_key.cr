require "../../hetzner/client"
require "../../hetzner/ssh_key/find"
require "../main"

class Configuration::Validators::AutoscalerSSHKey
  getter errors : Array(String) = [] of String
  getter settings : Configuration::Main
  getter hetzner_client : Hetzner::Client

  def initialize(@errors, @settings, @hetzner_client)
  end

  def validate
    return unless autoscaling_in_use?

    begin
      existing_ssh_key = Hetzner::SSHKey::Find.new(hetzner_client, settings.cluster_name, settings.networking.ssh.public_key_path).run
    rescue ex
      errors << "Unable to verify SSH key for autoscaler: #{ex.message}"
      return
    end

    return unless existing_ssh_key
    return if existing_ssh_key.name == settings.cluster_name

    errors << "Cluster autoscaler requires an SSH key named '#{settings.cluster_name}' in Hetzner. A key with the same fingerprint exists as '#{existing_ssh_key.name}', so hetzner-k3s will not create '#{settings.cluster_name}'. Autoscaled nodes will be created without SSH keys. Rename or delete the existing key, or change cluster_name."
  end

  private def autoscaling_in_use?
    return false unless settings.addons.cluster_autoscaler.enabled?

    worker_node_pools = settings.worker_node_pools || [] of Configuration::Models::WorkerNodePool
    worker_node_pools.any?(&.autoscaling_enabled)
  end
end