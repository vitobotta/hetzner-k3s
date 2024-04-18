require "../client"
require "./find"
require "../../util"
require "../../configuration/settings/private_network"

class Hetzner::Network::Create
  include Util

  getter hetzner_client : Hetzner::Client
  getter network_name : String
  getter location : String
  getter network_finder : Hetzner::Network::Find
  getter locations : Array(Hetzner::Location)
  getter private_network : Configuration::Settings::PrivateNetwork

  def initialize(@hetzner_client, @network_name, @location, @locations, @private_network)
    @network_finder = Hetzner::Network::Find.new(@hetzner_client, @network_name)
  end

  def run
    network = network_finder.run

    if network
      log_line "Private network already exists, skipping create"
    else
      log_line "Creating private network..."

      hetzner_client.post("/networks", network_config)
      network = network_finder.run

      log_line "...private network created"
    end

    network.not_nil!

  rescue ex : Crest::RequestFailed
    STDERR.puts "[#{default_log_prefix}] Failed to create network: #{ex.message}"
    exit 1
  end

  private def network_config
    network_zone = locations.find { |l| l.name == location }.not_nil!.network_zone

    {
      name: network_name,
      ip_range: private_network.subnet,
      subnets: [
        {
          ip_range: private_network.subnet,
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
