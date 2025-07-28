require "../client"
require "./find"
require "../../util"
require "../../configuration/main"
require "../../configuration/networking"

class Hetzner::Network::Create
  include Util

  getter hetzner_client : Hetzner::Client
  getter settings : Configuration::Main
  getter network_name : String
  getter network_zone : String
  getter network_finder : Hetzner::Network::Find

  def initialize(@settings, @hetzner_client, @network_name, @network_zone)
    @network_finder = Hetzner::Network::Find.new(hetzner_client, network_name)
  end

  def run
    network = network_finder.run

    return network if network

    log_line "Creating private network..."
    create_network
    log_line "...private network created"
    network_finder.run.not_nil!
  end

  private def network_config
    {
      :name => network_name,
      :ip_range => settings.networking.private_network.subnet,
      :subnets => [
        {
          :ip_range => settings.networking.private_network.subnet,
          :network_zone => network_zone,
          :type => "cloud"
        }
      ]
    }
  end

  private def create_network
    Retriable.retry(max_attempts: 10, backoff: false, base_interval: 5.seconds) do
      success, response = hetzner_client.post("/networks", network_config)

      unless success
        STDERR.puts "[#{default_log_prefix}] Failed to create private network: #{response}"
        STDERR.puts "[#{default_log_prefix}] Retrying to create private network in 5 seconds..."
        raise "Failed to create private network"
      end
    end
  end

  private def default_log_prefix
    "Private Network"
  end
end
