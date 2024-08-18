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

      Retriable.retry(max_attempts: 10, backoff: false, base_interval: 5.seconds) do
        success, response = hetzner_client.delete("/networks", network.id)

        unless success
          STDERR.puts "[#{default_log_prefix}] Failed to delete private network: #{response}"
          STDERR.puts "[#{default_log_prefix}] Retrying to delete private network in 5 seconds..."
          raise "Failed to delete private network"
        end
      end

      log_line "...private network deleted"
    else
      log_line "Private network does not exist, skipping delete"
    end

    network_name
  end

  private def default_log_prefix
    "Private network"
  end
end
