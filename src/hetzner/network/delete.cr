require "../client"
require "./find"
require "../../util"

class Hetzner::Network::Delete
  include Util

  getter hetzner_client : Hetzner::Client
  getter network_name : String
  getter network_finder : Hetzner::Network::Find

  def initialize(@hetzner_client, @network_name)
    @network_finder = Hetzner::Network::Find.new(@hetzner_client, @network_name)
  end

  def run
    if network = network_finder.run
      log_line "Deleting private network..."

      hetzner_client.delete("/networks", network.id)

      log_line "...private network deleted"
    else
      log_line "Private network does not exist, skipping delete"
    end

    network_name

  rescue ex : Crest::RequestFailed
    STDERR.puts "[#{default_log_prefix}] Failed to delete network: #{ex.message}"
    exit 1
  end

  private def default_log_prefix
    "Private network"
  end
end
