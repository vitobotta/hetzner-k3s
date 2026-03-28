require "../../hetzner/client"
require "../models/networking"
require "../models/networking_config/cni"
require "../models/networking_config/allowed_networks"
require "../models/networking_config/private_network"
require "../models/networking_config/public_network"
require "../models/networking_config/ssh"
require "./networking_config/cni"
require "./networking_config/allowed_networks"
require "./networking_config/node_port_range"
require "./networking_config/private_network"
require "./networking_config/public_network"
require "./networking_config/ssh"

class Configuration::Validators::Networking
  getter errors : Array(String)
  getter networking : Configuration::Models::Networking
  getter settings : Configuration::Main
  getter hetzner_client : Hetzner::Client
  getter private_network : Configuration::Models::NetworkingConfig::PrivateNetwork
  getter skip_current_ip_validation : Bool = false

  def initialize(@errors, @networking, @settings, @hetzner_client, @private_network, @skip_current_ip_validation = false)
  end

  def validate
    Configuration::Validators::NetworkingConfig::CNI.new(errors, networking.cni, private_network).validate
    Configuration::Validators::NetworkingConfig::AllowedNetworks.new(
      errors,
      networking.allowed_networks,
      skip_current_ip_validation: skip_current_ip_validation
    ).validate
    Configuration::Validators::NetworkingConfig::NodePortRange.new(errors, networking.node_port_range).validate
    Configuration::Validators::NetworkingConfig::PrivateNetwork.new(errors, private_network, hetzner_client).validate
    Configuration::Validators::NetworkingConfig::PublicNetwork.new(errors, networking.public_network, settings).validate
    Configuration::Validators::NetworkingConfig::SSH.new(errors, networking.ssh, hetzner_client, settings.cluster_name).validate
    validate_tailscale
  end

  private def validate_tailscale
    ssh = networking.ssh
    return unless ssh.use_tailscale

    if ssh.tailscale_hostname_suffix.empty?
      errors << "tailscale_hostname_suffix is required when use_tailscale is true (e.g. \"my-tailnet.ts.net\")"
    end

    if ssh.tailscale_auth_key.empty?
      errors << "A Tailscale auth key is required when use_tailscale is true. Set tailscale_auth_key in the configuration or the TAILSCALE_AUTH_KEY environment variable."
    end

    if !networking.public_network.ipv4 && !networking.public_network.ipv6
      errors << "When use_tailscale is true and ipv4 is disabled, ipv6 must be enabled so nodes can reach the Tailscale coordination server."
    end
  end
end
