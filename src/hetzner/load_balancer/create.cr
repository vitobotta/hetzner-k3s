require "../client"
require "./find"
require "../../util"

class Hetzner::LoadBalancer::Create
  include Util

  getter settings : Configuration::Main
  getter hetzner_client : Hetzner::Client
  getter cluster_name : String
  getter location : String
  getter network_id : Int64? = 0
  getter load_balancer_finder : Hetzner::LoadBalancer::Find
  getter load_balancer_name : String do
    "#{cluster_name}-api"
  end

  def initialize(@settings, @hetzner_client, @location, @network_id)
    @cluster_name = settings.cluster_name
    @load_balancer_finder = Hetzner::LoadBalancer::Find.new(@hetzner_client, load_balancer_name)
  end

  def run
    load_balancer = load_balancer_finder.run

    if load_balancer
      log_line "Load balancer for API server already exists, skipping create"
    else
      log_line "Creating load balancer for API server..."
      create_load_balancer
      load_balancer = wait_for_load_balancer_public_ip
      log_line "...load balancer for API server created"
    end

    load_balancer.not_nil!
  end

  private def create_load_balancer
    Retriable.retry(max_attempts: 10, backoff: false, base_interval: 5.seconds) do
      success, response = hetzner_client.post("/load_balancers", load_balancer_config)

      unless success
        STDERR.puts "[#{default_log_prefix}] Failed to create load balancer: #{response}"
        STDERR.puts "[#{default_log_prefix}] Retrying to create load balancer in 5 seconds..."
        raise "Failed to create load balancer"
      end
    end
  end

  private def wait_for_load_balancer_public_ip
    loop do
      load_balancer = load_balancer_finder.run
      break load_balancer if load_balancer.try(&.public_ip_address)
      sleep 1.seconds
    end
  end

  private def load_balancer_config
    if settings.networking.private_network.enabled
      {
        :algorithm => {
          :type => "round_robin"
        },
        :load_balancer_type => "lb11",
        :location => location,
        :name => load_balancer_name,
        :network => network_id,
        :public_interface => true,
        :services => [
          {
            :destination_port => 6443,
            :listen_port => 6443,
            :protocol => "tcp",
            :proxyprotocol => false
          }
        ],
        :targets => [
          {
            :label_selector => {
              :selector => "cluster=#{cluster_name},role=master"
            },
            :type => "label_selector",
            :use_private_ip => true
          }
        ]
      }
    else
      {
        :algorithm => {
          :type => "round_robin"
        },
        :load_balancer_type => "lb11",
        :location => location,
        :name => load_balancer_name,
        :public_interface => true,
        :services => [
          {
            :destination_port => 6443,
            :listen_port => 6443,
            :protocol => "tcp",
            :proxyprotocol => false
          }
        ],
        :targets => [
          {
            :label_selector => {
              :selector => "cluster=#{cluster_name},role=master"
            },
            :type => "label_selector",
            :use_private_ip => false
          }
        ]
      }
    end
  end

  private def default_log_prefix
    "API Load balancer"
  end
end
