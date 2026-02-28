require "../client"
require "./find"
require "../../util"
require "../../configuration/models/networking"

class Hetzner::Firewall::Create
  include Util

  private getter settings : Configuration::Main
  private getter masters : Array(Hetzner::Instance)
  private getter hetzner_client : Hetzner::Client
  private getter firewall_name : String
  private getter firewall_finder : Hetzner::Firewall::Find
  private getter private_network : Configuration::Models::NetworkingConfig::PrivateNetwork
  private getter ssh : Configuration::Models::NetworkingConfig::SSH
  private getter allowed_networks : Configuration::Models::NetworkingConfig::AllowedNetworks
  private getter node_port_range : String
  private getter node_port_firewall_enabled : Bool

  def initialize(
    @settings,
    @hetzner_client,
    @firewall_name,
    @masters
  )
    @private_network = settings.networking.private_network
    @ssh = settings.networking.ssh
    @allowed_networks = settings.networking.allowed_networks
    @node_port_range = settings.networking.node_port_range
    @node_port_firewall_enabled = settings.networking.node_port_firewall_enabled
    @firewall_finder = Hetzner::Firewall::Find.new(hetzner_client, firewall_name)
  end

  def run
    firewall = firewall_finder.run

    return handle_firewall_update(firewall) if firewall

    log_line "Creating firewall..."
    create_firewall
    log_line "...firewall created"
    firewall_finder.run.not_nil!
  end

  private def handle_firewall_update(firewall)
    log_line "Updating firewall..."
    update_firewall(firewall.id)
    log_line "...firewall updated"
    firewall
  end

  private def create_firewall
    Retriable.retry(max_attempts: 10, backoff: false, base_interval: 5.seconds) do
      success, response = hetzner_client.post("/firewalls", firewall_config)

      unless success
        STDERR.puts "[#{default_log_prefix}] Failed to create firewall: #{response}"
        STDERR.puts "[#{default_log_prefix}] Retrying to create firewall in 5 seconds..."
        raise "Failed to create firewall"
      end
    end
  end

  private def update_firewall(firewall_id)
    Retriable.retry(max_attempts: 10, backoff: false, base_interval: 5.seconds) do
      success, response = hetzner_client.post("/firewalls/#{firewall_id}/actions/set_rules", firewall_config)

      unless success
        STDERR.puts "[#{default_log_prefix}] Failed to update firewall: #{response}"
        STDERR.puts "[#{default_log_prefix}] Retrying to update firewall in 5 seconds..."
        raise "Failed to update firewall"
      end
    end
  end

  private def firewall_config
    rules = [
      {
        :description     => "Allow SSH port",
        :direction       => "in",
        :protocol        => "tcp",
        :port            => ssh.port.to_s,
        :source_ips      => allowed_networks.ssh,
        :destination_ips => [] of String,
      },
      {
        :description => "Allow ICMP (ping)",
        :direction   => "in",
        :protocol    => "icmp",
        :source_ips  => [
          "0.0.0.0/0",
          "::/0",
        ],
        :destination_ips => [] of String,
      },
      # NodePort rules are optional and can be disabled via config.
    ]

    if node_port_firewall_enabled
      rules += [
        {
          :description => "Node port range TCP",
          :direction   => "in",
          :protocol    => "tcp",
          :port        => node_port_range,
          :source_ips  => [
            "0.0.0.0/0",
            "::/0",
          ],
          :destination_ips => [] of String,
        },
        {
          :description => "Node port range UDP",
          :direction   => "in",
          :protocol    => "udp",
          :port        => node_port_range,
          :source_ips  => [
            "0.0.0.0/0",
            "::/0",
          ],
          :destination_ips => [] of String,
        },
      ]
    end

    if private_network.try(&.enabled)
      rules += [
        {
          :description     => "Allow Kubernetes API access to allowed networks",
          :direction       => "in",
          :protocol        => "tcp",
          :port            => "6443",
          :source_ips      => allowed_networks.api,
          :destination_ips => [] of String,
        },
        {
          :description     => "Allow all TCP traffic between nodes on the private network",
          :direction       => "in",
          :protocol        => "tcp",
          :port            => "any",
          :source_ips      => [private_network.subnet],
          :destination_ips => [] of String,
        },
        {
          :description     => "Allow all UDP traffic between nodes on the private network",
          :direction       => "in",
          :protocol        => "udp",
          :port            => "any",
          :source_ips      => [private_network.subnet],
          :destination_ips => [] of String,
        },
      ]
    else
      rules << {
        :description => "Allow port 6443 (Kubernetes API server) between masters",
        :direction   => "in",
        :protocol    => "tcp",
        :port        => "6443",
        :source_ips  => [
          "0.0.0.0/0",
          "::/0",
        ],
        :destination_ips => [] of String,
      }

      wireguard_port = settings.networking.cni.cilium? ? "51871" : "51820"

      rules << {
        :description => "Allow wireguard traffic (Cilium)",
        :direction   => "in",
        :protocol    => "tcp",
        :port        => wireguard_port,
        :source_ips  => [
          "0.0.0.0/0",
          "::/0",
        ],
        :destination_ips => [] of String,
      }

      if masters.size > 0 && settings.datastore.mode == "etcd"
        master_ips = masters.map do |master|
          "#{master.public_ip_address}/32"
        end

        rules << {
          :description     => "Allow etcd traffic between masters",
          :direction       => "in",
          :protocol        => "tcp",
          :port            => "2379",
          :source_ips      => master_ips,
          :destination_ips => [] of String,
        }

        rules << {
          :description     => "Allow etcd traffic between masters",
          :direction       => "in",
          :protocol        => "tcp",
          :port            => "2380",
          :source_ips      => master_ips,
          :destination_ips => [] of String,
        }
      end
    end

    if settings.addons.embedded_registry_mirror.enabled && !private_network.try(&.enabled)
      rules << {
        :description => "Allow traffic between nodes for peer-to-peer image distribution",
        :direction   => "in",
        :protocol    => "tcp",
        :port        => "5001",
        :source_ips  => [
          "0.0.0.0/0",
          "::/0",
        ],
        :destination_ips => [] of String,
      }
    end

    # Add any user-defined custom firewall rules (networking.allowed_networks.custom_firewall_rules)
    allowed_networks.custom_firewall_rules.each do |custom_rule|
      rules << {
        :description     => custom_rule.effective_description,
        :direction       => custom_rule.direction,
        :protocol        => custom_rule.protocol,
        :port            => custom_rule.port,
        :source_ips      => custom_rule.direction == "in" ? custom_rule.source_ips : ([] of String),
        :destination_ips => custom_rule.direction == "out" ? custom_rule.destination_ips : ([] of String),
      }
    end

    # Hetzner Cloud currently allows up to 50 entries per firewall. Fail fast if we exceed this hard limit.
    if rules.size > 50
      raise "Generated firewall would contain #{rules.size} rules, which exceeds the 50-rule limit imposed by Hetzner Cloud. Please reduce the number of custom firewall rules or consolidate ranges."
    end

    {
      :name     => firewall_name,
      :rules    => rules,
      :apply_to => [
        {
          :label_selector => {
            :selector => "cluster=#{settings.cluster_name}",
          },
          :type => "label_selector",
        },
      ],
    }
  end

  private def default_log_prefix
    "Firewall"
  end
end
