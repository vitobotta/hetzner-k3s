require "../client"
require "./find"
require "../../util"

class Hetzner::LoadBalancer::Create
  include Util

  private getter settings : Configuration::Main
  private getter hetzner_client : Hetzner::Client
  private getter cluster_name : String
  private getter location : String
  private getter network_id : Int64? = 0
  private getter load_balancer_finder : Hetzner::LoadBalancer::Find
  private getter load_balancer_name : String do
    "#{cluster_name}-api"
  end

  def initialize(@settings, @hetzner_client, @location, @network_id)
    @cluster_name = settings.cluster_name
    @load_balancer_finder = Hetzner::LoadBalancer::Find.new(@hetzner_client, load_balancer_name)
  end

  def run
    load_balancer = load_balancer_finder.run

    if load_balancer
      return load_balancer unless settings.disable_public_interface_for_the_kubernetes_api_load_balancer

      return make_private(load_balancer)
    end

    log_line "Creating load balancer for API server..."
    create_load_balancer
    load_balancer = wait_for("the IP address of the load balancer to become available") { |lb| ip_address_ready?(lb) }
    log_line "...load balancer for API server created"
    load_balancer
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

  # Load balancers created by this tool with the private network enabled are already attached to
  # it and target the masters via private IPs, so only the public interface needs to be disabled.
  # Anything else was changed outside this tool and is not converged automatically.
  private def make_private(load_balancer : Hetzner::LoadBalancer) : Hetzner::LoadBalancer
    return load_balancer unless load_balancer.public_interface_enabled?

    unless load_balancer.attached_to_network?(network_id.not_nil!)
      fail_with "The load balancer is not attached to the configured private network. Attach it in the Hetzner console (or delete it so that it can be recreated), then run create again."
    end

    unless load_balancer.targets.all? { |target| target.use_private_ip == true }
      fail_with "The load balancer has targets that do not use private IPs, which prevents disabling its public interface. Remove them or switch them to private IPs in the Hetzner console, then run create again."
    end

    log_line "Disabling public interface of load balancer for API server..."

    Retriable.retry(max_attempts: 10, backoff: false, base_interval: 5.seconds) do
      success, response = hetzner_client.post("/load_balancers/#{load_balancer.id}/actions/disable_public_interface", {} of String => String)

      unless success
        STDERR.puts "[#{default_log_prefix}] Failed to disable public interface of load balancer: #{response}"
        STDERR.puts "[#{default_log_prefix}] Retrying to disable public interface of load balancer in 5 seconds..."
        raise "Failed to disable public interface of load balancer"
      end
    end

    load_balancer = wait_for("disable the public interface of the load balancer") { |lb| !lb.public_interface_enabled? }
    log_line "...public interface of load balancer for API server disabled"
    load_balancer
  end

  private def wait_for(description : String, &) : Hetzner::LoadBalancer
    deadline = Time.monotonic + 5.minutes

    loop do
      load_balancer = load_balancer_finder.run
      break load_balancer if load_balancer && yield(load_balancer)

      fail_with "Timed out waiting to #{description}" if Time.monotonic > deadline

      sleep 1.seconds
    end
  end

  private def fail_with(message : String) : NoReturn
    STDERR.puts "[#{default_log_prefix}] #{message}"
    raise message
  end

  private def ip_address_ready?(load_balancer : Hetzner::LoadBalancer)
    !load_balancer.ip_address(settings.use_private_ip_for_the_kubernetes_api_load_balancer?).nil?
  end

  private def load_balancer_config
    private_network_enabled = settings.networking.private_network.enabled

    config = {
      :algorithm => {
        :type => "round_robin",
      },
      :load_balancer_type => "lb11",
      :location           => location,
      :name               => load_balancer_name,
      :public_interface   => !settings.disable_public_interface_for_the_kubernetes_api_load_balancer,
      :services           => [
        {
          :destination_port => 6443,
          :listen_port      => 6443,
          :protocol         => "tcp",
          :proxyprotocol    => false,
        },
      ],
      :targets => [
        {
          :label_selector => {
            :selector => "cluster=#{cluster_name},role=master",
          },
          :type           => "label_selector",
          :use_private_ip => private_network_enabled,
        },
      ],
    }

    config = config.merge({:network => network_id}) if private_network_enabled

    config
  end

  private def default_log_prefix
    "API Load balancer"
  end
end
