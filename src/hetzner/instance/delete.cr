require "../client"
require "../instance"
require "../instances_list"
require "./find"
require "../../util"

class Hetzner::Instance::Delete
  include Util

  getter hetzner_client : Hetzner::Client
  getter instance_name : String
  getter instance_finder : Hetzner::Instance::Find

  def initialize(@hetzner_client, @instance_name)
    @instance_finder = Hetzner::Instance::Find.new(@hetzner_client, @instance_name)
  end

  def run
    if instance = instance_finder.run
      log_line "Deleting instance #{instance_name}..."

      hetzner_client.delete("/servers", instance.id)

      log_line "...instance #{instance_name} deleted"
    else
      log_line "Instance #{instance_name} does not exist, skipping delete"
    end

    instance_name

  rescue ex : Crest::RequestFailed
    STDERR.puts "[#{default_log_prefix}] Failed to delete instance: #{ex.message}"
    exit 1
  end

  private def default_log_prefix
    "Instance #{instance_name}"
  end
end
