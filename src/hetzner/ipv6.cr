require "json"

class Hetzner::Ipv6
  include JSON::Serializable

  property ip : String?
  property blocked : Bool?

  def initialize(ip : String)
    @ip = ip
  end

  # `ip` is the /64 network the API returns for a server, for example `2001:db8:1234::/64`, not an
  # address. Hetzner puts the first address of that network on the interface, so that is what SSH,
  # `--server`, the kubeconfig and the TLS SAN need.
  def address : String?
    network = ip
    return nil unless network

    prefix = network.split("/").first
    return nil if prefix.empty?

    return "#{prefix}1" if prefix.ends_with?(":")

    groups = prefix.split(":")
    groups[-1] = (groups[-1].to_i(16) + 1).to_s(16)
    groups.join(":")
  end
end
