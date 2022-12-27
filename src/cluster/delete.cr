require "../configuration/main"
require "../hetzner/placement_group"
require "../hetzner/ssh_key"
require "../hetzner/firewall"
require "../hetzner/network"
require "../hetzner/server"

class Clusters::DeleteCluster
  private getter configuration : Configuration::Main

  def initialize(@configuration)

  end

  def run

  end
end
