require "../client"
require "./find"
require "../../util"
require "../../configuration/networking"

class Hetzner::Firewall::Create
  include Util

  private getter settings : Configuration::Main
  private getter masters : Array(Hetzner::Instance)
  private getter hetzner_client : Hetzner::Client
  private getter firewall_name : String
  private getter firewall_finder : Hetzner::Firewall::Find
  private getter private_network : Configuration::NetworkingComponents::PrivateNetwork
  private getter ssh : Configuration::NetworkingComponents::SSH
  private getter allowed_networks : Configuration::NetworkingComponents::AllowedNetworks

  def initialize(
    @settings,
    @hetzner_client,
    @firewall_name,
    @masters
  )
    @private_network = settings.networking.private_network
    @ssh = settings.networking.ssh
    @allowed_networks = settings.networking.allowed_networks
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
      {
        :description => "Node port range TCP",
        :direction   => "in",
        :protocol    => "tcp",
        :port        => "30000-32767",
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
        :port        => "30000-32767",
        :source_ips  => [
          "0.0.0.0/0",
          "::/0",
        ],
        :destination_ips => [] of String,
      },
    ]

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

    if settings.embedded_registry_mirror.enabled && !private_network.try(&.enabled)
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
