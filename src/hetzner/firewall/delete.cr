require "../client"
require "./find"
require "../../util"

class Hetzner::Firewall::Delete
  include Util

  getter hetzner_client : Hetzner::Client
  getter firewall_name : String
  getter firewall_finder : Hetzner::Firewall::Find

  def initialize(@hetzner_client, @firewall_name)
    @firewall_finder = Hetzner::Firewall::Find.new(@hetzner_client, @firewall_name)
  end

  def run
    firewall = firewall_finder.run

    if firewall
      log_line "Deleting firewall..."
      delete_firewall(firewall.id)
      log_line "...firewall deleted."
    else
      log_line "Firewall does not exist, skipping delete"
    end

    firewall_name
  end

  private def delete_firewall(firewall_id)
    hetzner_client.delete("/firewalls", firewall_id)
  rescue ex : Crest::RequestFailed
    STDERR.puts "[#{default_log_prefix}] Failed to delete firewall: #{ex.message}"
    exit 1
  end

  private def default_log_prefix
    "Firewall"
  end
end
