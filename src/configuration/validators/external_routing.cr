require "../main"

class Configuration::Validators::ExternalRouting
  def initialize(@errors : Array(String), @settings : Configuration::Main)
  end

  def validate
    return unless @settings.networking.private_network.external_routing

    unless @settings.networking.private_network.enabled
      @errors << "networking.private_network.external_routing requires networking.private_network.enabled to be true"
    end

    unless @settings.worker_node_pools.any?(&.external?)
      @errors << "networking.private_network.external_routing requires at least one external worker node pool (instance_type: external)"
    end
  end
end
