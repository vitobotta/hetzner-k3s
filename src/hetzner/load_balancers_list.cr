require "./load_balancer"

class Hetzner::LoadBalancersList
  include JSON::Serializable

  property load_balancers : Array(Hetzner::LoadBalancer)
end
