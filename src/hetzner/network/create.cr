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
  getter location : String
  getter network_finder : Hetzner::Network::Find
  getter locations : Array(Hetzner::Location)

  def initialize(@settings, @hetzner_client, @network_name, @locations)
    @location = settings.masters_pool.location
    @network_finder = Hetzner::Network::Find.new(hetzner_client, network_name)
  end

  def run
    network = network_finder.run

    if network
      log_line "Private network already exists, skipping create"
    else
      log_line "Creating private network..."

      Retriable.retry(max_attempts: 10, backoff: false, base_interval: 5.seconds) do
        success, response = hetzner_client.post("/networks", network_config)

        unless success
          STDERR.puts "[#{default_log_prefix}] Failed to create private network: #{response}"
          STDERR.puts "[#{default_log_prefix}] Retrying to create private network in 5 seconds..."
          raise "Failed to create private network"
        end
      end

      network = network_finder.run

      log_line "...private network created"
    end

    network.not_nil!
  end

  private def network_config
    network_zone = locations.find { |l| l.name == location }.not_nil!.network_zone

    {
      name: network_name,
      ip_range: settings.networking.private_network.subnet,
      subnets: [
        {
          ip_range: settings.networking.private_network.subnet,
          network_zone: network_zone,
          type: "cloud"
        }
      ]
    }
  end

  private def default_log_prefix
    "Private Network"
  end
end
