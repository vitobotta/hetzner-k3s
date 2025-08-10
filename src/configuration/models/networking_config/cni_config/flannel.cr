class Configuration::NetworkingConfig::Flannel
  include YAML::Serializable
  include YAML::Serializable::Unmapped

  getter disable_kube_proxy : Bool = false

  def initialize
  end

  def disable_kube_proxy? : Bool
    disable_kube_proxy
  end
end
