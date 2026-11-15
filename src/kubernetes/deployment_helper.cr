require "../hetzner/instance"
require "../hetzner/load_balancer"

module Kubernetes::DeploymentHelper
  def self.api_server_ip_address(instance : Hetzner::Instance) : String
    instance.private_ip_address || instance.public_ip_address.not_nil!
  end

  def api_server_ip_address(instance : Hetzner::Instance) : String
    DeploymentHelper.api_server_ip_address(instance)
  end

  # The address a joining worker registers against: the API load balancer when there is one, so
  # a worker (an autoscaled one included) can join while the first master is down; the first
  # master otherwise. The load balancer address is the one the masters' TLS SANs and the
  # kubeconfig already carry (KubeconfigManager), so no master's certificate changes.
  def self.join_ip_address(first_master : Hetzner::Instance, load_balancer : Hetzner::LoadBalancer?, use_private_ip : Bool) : String
    if load_balancer
      address = use_private_ip ? load_balancer.private_ip_address : load_balancer.public_ip_address
      return address if address
    end

    api_server_ip_address(first_master)
  end

  def join_ip_address(first_master : Hetzner::Instance, load_balancer : Hetzner::LoadBalancer?, use_private_ip : Bool) : String
    DeploymentHelper.join_ip_address(first_master, load_balancer, use_private_ip)
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
