require "../main"

class Configuration::Validators::ApiLoadBalancer
  getter errors : Array(String)
  getter settings : Configuration::Main

  def initialize(@errors, @settings)
  end

  def validate
    return unless settings.disable_public_interface_for_the_kubernetes_api_load_balancer

    unless settings.create_load_balancer_for_the_kubernetes_api
      errors << "disable_public_interface_for_the_kubernetes_api_load_balancer requires create_load_balancer_for_the_kubernetes_api to be enabled"
    end

    unless settings.networking.private_network.enabled
      errors << "disable_public_interface_for_the_kubernetes_api_load_balancer requires the private network to be enabled"
    end

    unless settings.masters_pool.instance_count > 1
      errors << "disable_public_interface_for_the_kubernetes_api_load_balancer requires a multi-master cluster, since the load balancer for the Kubernetes API is only created when there is more than one master"
    end
  end
end
