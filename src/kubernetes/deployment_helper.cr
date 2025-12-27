require "../hetzner/instance"

module Kubernetes::DeploymentHelper
  def self.api_server_ip_address(instance : Hetzner::Instance) : String
    instance.private_ip_address || instance.public_ip_address.not_nil!
  end

  def api_server_ip_address(instance : Hetzner::Instance) : String
    DeploymentHelper.api_server_ip_address(instance)
  end
end

module Kubernetes::SSHDeploymentHelper
  include Kubernetes::DeploymentHelper

  CLOUD_INIT_WAIT_SCRIPT = {{ read_file("#{__DIR__}/../../templates/cloud_init_wait_script.sh") }}

  abstract def settings : Configuration::Main
  abstract def ssh : ::Util::SSH

  def wait_for_cloud_init(instance : Hetzner::Instance)
    ssh.run(instance, settings.networking.ssh.port, CLOUD_INIT_WAIT_SCRIPT, settings.networking.ssh.use_agent)
  end

  def deploy_to_instance(instance : Hetzner::Instance, script : String) : String
    ssh.run(instance, settings.networking.ssh.port, script, settings.networking.ssh.use_agent)
  end
end
