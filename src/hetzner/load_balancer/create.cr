require "../client"
require "../load_balancers_list"
require "./find"
require "../../util"

class Hetzner::LoadBalancer::Create
  include Util

  # Distinguishes the deliberate retry-on-action-failure path from unexpected exceptions,
  # which should propagate instead of re-posting the action; transient transport errors
  # are retried alongside it.
  private class ActionFailed < Exception
  end

  private getter settings : Configuration::Main
  private getter hetzner_client : Hetzner::Client
  private getter cluster_name : String
  private getter location : String
  private getter network_id : Int64? = 0
  private getter load_balancer_finder : Hetzner::LoadBalancer::Find
  private getter load_balancer_name : String do
    "#{cluster_name}-api"
  end
  private getter master_target_selector : String do
    "cluster=#{cluster_name},role=master"
  end
  private property last_fetch_failure : String?

  def initialize(@settings, @hetzner_client, @location, @network_id)
    @cluster_name = settings.cluster_name
    @load_balancer_finder = Hetzner::LoadBalancer::Find.new(@hetzner_client, load_balancer_name)
  end

  def run
    load_balancer = load_balancer_finder.run

    if load_balancer
      load_balancer = reconcile_existing_load_balancer(load_balancer)
    else
      log_line "Creating load balancer for API server..."

      existing_load_balancer, created_load_balancer_id = create_load_balancer

      if existing_load_balancer
        # The load balancer may have been missed by the initial lookup or created by an earlier
        # attempt whose response was lost; reconcile it like any other existing load balancer.
        log_line "...load balancer for API server found, checking its configuration"
        load_balancer = reconcile_existing_load_balancer(existing_load_balancer)
      else
        load_balancer = wait_for_ip_ready(created_load_balancer_id)
        log_line "...load balancer for API server created"
      end
    end

    load_balancer
  end

  # Returns {existing load balancer, created load balancer ID}: the former when the create
  # failed because one with the same name already exists, otherwise the latter, so that the
  # subsequent polling is not satisfied by a same-named replacement.
  private def create_load_balancer : {Hetzner::LoadBalancer?, Int32?}
    existing_load_balancer = nil

    response = post_with_retries("/load_balancers", load_balancer_config, "create load balancer") do
      # The create may have already succeeded in a previous attempt whose response was lost,
      # or the load balancer may exist but have been missed by the initial lookup.
      _, existing_load_balancer = fetch_load_balancer
      !existing_load_balancer.nil?
    end

    {existing_load_balancer, existing_load_balancer ? nil : parse_load_balancer_id(response)}
  end

  private def parse_load_balancer_id(response : String) : Int32?
    JSON.parse(response).dig?("load_balancer", "id").try(&.as_i?)
  rescue JSON::ParseException
    nil
  end

  private def reconcile_existing_load_balancer(load_balancer : Hetzner::LoadBalancer) : Hetzner::LoadBalancer
    if settings.disable_public_interface_for_the_kubernetes_api_load_balancer
      ensure_public_interface_can_be_disabled(load_balancer) if load_balancer.public_interface_enabled?
      load_balancer = ensure_network_attachment(load_balancer)
      load_balancer = reconcile_master_target(load_balancer)
      load_balancer = disable_public_interface(load_balancer) if load_balancer.public_interface_enabled?
    else
      unless load_balancer.public_interface_enabled?
        unless settings.networking.private_network.enabled
          STDERR.puts "[#{default_log_prefix}] The public interface of the load balancer is disabled, but disable_public_interface_for_the_kubernetes_api_load_balancer is not set and the private network is disabled, so the load balancer has no usable IP address. Re-enable the public interface in the Hetzner console or adjust the configuration, then run create again."
          raise "The load balancer has no usable IP address for the current configuration"
        end

        log_line "The public interface of the load balancer is disabled, but disable_public_interface_for_the_kubernetes_api_load_balancer is not set. It will not be re-enabled automatically; if the Kubernetes API should be reachable via the public network, enable it in the Hetzner console and then run create again so that the kubeconfig and the API server certificate use the public IP address."
      end

      needs_private_ip = settings.use_private_ip_for_the_kubernetes_api_load_balancer? || !load_balancer.public_interface_enabled?

      if needs_private_ip && (desired_network_id = network_id) && !load_balancer.private_net.empty? && !load_balancer.attached_to_network?(desired_network_id)
        raise_wrong_network_error("A private IP address of the load balancer is going to be used, but the load balancer is attached to a different private network than the one configured, so that address would not be reachable from the cluster.")
      end

      # An unattached load balancer would make the private IP wait below spin forever, and a
      # restored target can only use private IPs once the load balancer is attached, so attach
      # first when a private IP is going to be used or the lost target is about to be restored.
      # A load balancer attached to a different network is left untouched on this path, as
      # before this feature was introduced.
      if (desired_network_id = network_id) && load_balancer.private_net.empty? && (needs_private_ip || load_balancer.targets.empty?)
        load_balancer = attach_to_network(load_balancer, desired_network_id)
      end

      load_balancer = restore_missing_master_target(load_balancer)
    end

    ip_address_ready?(load_balancer) ? load_balancer : wait_for_ip_ready(load_balancer.id)
  end

  private def ensure_network_attachment(load_balancer : Hetzner::LoadBalancer) : Hetzner::LoadBalancer
    desired_network_id = network_id
    return load_balancer unless desired_network_id
    return load_balancer if load_balancer.attached_to_network?(desired_network_id)

    # Hetzner load balancers support a single network attachment, so an attachment to a different
    # network cannot be reconciled automatically without detaching it, which could be destructive.
    unless load_balancer.private_net.empty?
      raise_wrong_network_error("The load balancer is attached to a different private network than the one configured.")
    end

    attach_to_network(load_balancer, desired_network_id)
  end

  private def raise_wrong_network_error(reason : String) : NoReturn
    STDERR.puts "[#{default_log_prefix}] #{reason} Detach it in the Hetzner console (or delete the load balancer so that it can be recreated), then run create again."
    raise "The load balancer is attached to a different private network than the one configured"
  end

  private def attach_to_network(load_balancer : Hetzner::LoadBalancer, desired_network_id : Int64) : Hetzner::LoadBalancer
    log_line "Attaching load balancer for API server to the private network..."

    load_balancer = run_load_balancer_action(load_balancer, "attach_to_network", {:network => desired_network_id}, "attach load balancer to the private network", "the load balancer to be attached to the private network") do |lb|
      lb.private_net.any? { |net| net.network == desired_network_id && net.ip }
    end

    log_line "...load balancer for API server attached to the private network"
    load_balancer
  end

  # Hetzner refuses to disable the public interface while any target uses public IPs, and
  # additional targets are not managed by this tool, so they cannot be converged automatically.
  # Checked before anything is mutated so that a load balancer that cannot be converged is left
  # untouched. Targets without a use_private_ip attribute (e.g. IP targets) cannot be classified
  # here; if one blocks the disable, the failure guidance in #disable_public_interface covers it.
  private def ensure_public_interface_can_be_disabled(load_balancer : Hetzner::LoadBalancer)
    return if load_balancer.targets.none? { |target| !master_target?(target) && target.use_private_ip == false }

    STDERR.puts "[#{default_log_prefix}] The public interface of the load balancer cannot be disabled because it has additional targets that do not use private IPs. Remove those targets in the Hetzner console (or switch them to private IPs), then run create again."
    raise "The load balancer has additional targets that do not use private IPs"
  end

  # The master target can only be switched to private IPs by removing and re-adding it (the
  # Hetzner API has no update action for targets), so this is written to converge across
  # interrupted runs: a target lost between the remove and the add is simply re-added. Unlike
  # on the flag-off path, this happens even when the load balancer has other targets — on this
  # path the master target is managed state, required for the load balancer to serve the
  # Kubernetes API privately.
  private def reconcile_master_target(load_balancer : Hetzner::LoadBalancer) : Hetzner::LoadBalancer
    return load_balancer if master_target_uses_private_ip?(load_balancer)

    restoring = load_balancer.targets.none? { |target| master_target?(target) }
    log_line restoring ? "Restoring missing load balancer target..." : "Updating load balancer target to use private IPs..."

    unless restoring
      load_balancer = run_load_balancer_action(load_balancer, "remove_target", master_target_params, "remove load balancer target", "the load balancer target to be removed") do |lb|
        lb.targets.none? { |target| master_target?(target) }
      end
    end

    load_balancer = run_load_balancer_action(load_balancer, "add_target", master_target_params(use_private_ip: true), "add load balancer target", "the load balancer target to use private IPs") do |lb|
      master_target_uses_private_ip?(lb)
    end

    log_line restoring ? "...load balancer target restored" : "...load balancer target updated to use private IPs"
    load_balancer
  end

  # Re-adds the master target when the load balancer has no targets at all, the state an earlier
  # run interrupted between remove_target and add_target leaves behind; any other target set is
  # assumed to be deliberate and left untouched.
  private def restore_missing_master_target(load_balancer : Hetzner::LoadBalancer) : Hetzner::LoadBalancer
    unless load_balancer.targets.empty?
      if load_balancer.targets.none? { |target| master_target?(target) }
        log_line "The load balancer does not have the managed master target; it will not be restored automatically because the load balancer has other targets. Add the target in the Hetzner console if the Kubernetes API should be reachable through the load balancer."
      end

      return load_balancer
    end

    log_line "Restoring missing load balancer target..."

    # A target can only use private IPs when the load balancer is attached to the configured network.
    desired_network_id = network_id
    use_private_ip = !desired_network_id.nil? && load_balancer.attached_to_network?(desired_network_id)

    unless use_private_ip
      unless settings.networking.public_network.ipv4
        STDERR.puts "[#{default_log_prefix}] The master target cannot be restored: the load balancer is not attached to the configured private network and the master nodes have no public IPs. Detach the load balancer in the Hetzner console (or delete it so that it can be recreated), then run create again."
        raise "The master target cannot be restored for the current configuration"
      end

      if settings.networking.private_network.enabled
        log_line "The load balancer is not attached to the configured private network, so the restored target will route to the masters over their public IPs."
      end
    end

    load_balancer = run_load_balancer_action(load_balancer, "add_target", master_target_params(use_private_ip: use_private_ip), "add load balancer target", "the load balancer target to be restored") do |lb|
      lb.targets.any? { |target| master_target?(target) }
    end

    log_line "...load balancer target restored"
    load_balancer
  end

  private def master_target?(target : Hetzner::LoadBalancer::Target)
    target.type == "label_selector" && target.label_selector.try(&.selector) == master_target_selector
  end

  private def master_target_uses_private_ip?(load_balancer : Hetzner::LoadBalancer)
    load_balancer.targets.any? { |target| master_target?(target) && target.use_private_ip == true }
  end

  private def master_target_params(use_private_ip : Bool? = nil)
    params = {:type => "label_selector", :label_selector => {:selector => master_target_selector}}

    use_private_ip.nil? ? params : params.merge({:use_private_ip => use_private_ip})
  end

  private def disable_public_interface(load_balancer : Hetzner::LoadBalancer) : Hetzner::LoadBalancer
    log_line "Disabling public interface of load balancer for API server..."

    load_balancer = run_load_balancer_action(load_balancer, "disable_public_interface", {} of String => String, "disable public interface of load balancer", "the public interface of the load balancer to be disabled") do |lb|
      !lb.public_interface_enabled?
    end

    log_line "...public interface of load balancer for API server disabled"
    load_balancer
  rescue ex : ActionFailed
    # E.g. an IP target pointing at a public IP address blocks the action, which the upfront
    # check cannot detect because such targets carry no use_private_ip attribute.
    STDERR.puts "[#{default_log_prefix}] The public interface of the load balancer could not be disabled. If the load balancer has targets that route over public IP addresses, remove them in the Hetzner console (or switch them to private IPs), then run create again."
    raise ex
  end

  # Posts the action, treating desired-state-already-reached as success when the POST fails (the
  # action may have succeeded in a previous attempt or run), then waits for the state change to
  # be reflected, verifying both with the same predicate.
  private def run_load_balancer_action(load_balancer : Hetzner::LoadBalancer, action : String, params, description : String, wait_description : String, & : Hetzner::LoadBalancer -> Bool) : Hetzner::LoadBalancer
    converged_load_balancer = nil
    gone_probes = 0

    post_with_retries("/load_balancers/#{load_balancer.id}/actions/#{action}", params, description) do
      fetched, current_load_balancer = fetch_load_balancer(load_balancer.id)

      if current_load_balancer
        gone_probes = 0

        if yield(current_load_balancer)
          converged_load_balancer = current_load_balancer
          next true
        end
      elsif fetched
        # Tolerate momentarily stale listings for about as long as the polling wait does; only
        # consecutive misses mean the load balancer is gone.
        gone_probes += 1

        if gone_probes >= 6
          STDERR.puts "[#{default_log_prefix}] The load balancer no longer exists; it may have been deleted while trying to #{description}"
          raise "The load balancer no longer exists"
        end
      else
        gone_probes = 0
      end

      false
    end

    if (current_load_balancer = converged_load_balancer)
      current_load_balancer
    else
      wait_for_load_balancer(wait_description, load_balancer.id) { |lb| yield(lb) }
    end
  end

  # POSTs with retries on transient transport errors and failed responses, logging each failed
  # attempt. On a failed response the block decides whether the attempt actually succeeded
  # (e.g. the desired state was reached by a previous attempt): returning true stops retrying.
  # Returns the response body, which is only meaningful when the POST itself succeeded.
  private def post_with_retries(path : String, params, description : String, &) : String
    Retriable.retry(max_attempts: 10, backoff: false, base_interval: 5.seconds, max_elapsed_time: 3.hours, on: [ActionFailed, IO::Error, OpenSSL::SSL::Error]) do
      success, response = begin
        hetzner_client.post(path, params)
      rescue ex : IO::Error | OpenSSL::SSL::Error
        STDERR.puts "[#{default_log_prefix}] Failed to #{description}: #{ex.message.try(&.presence) || ex.class.name}"
        STDERR.puts "[#{default_log_prefix}] Retrying to #{description} in 5 seconds..."
        raise ex
      end

      unless success
        next response if yield(response)

        STDERR.puts "[#{default_log_prefix}] Failed to #{description}: #{response}"
        STDERR.puts "[#{default_log_prefix}] Retrying to #{description} in 5 seconds..."
        raise ActionFailed.new("Failed to #{description}")
      end

      response
    end
  end

  private def wait_for_ip_ready(id : Int32? = nil)
    wait_for_load_balancer("the IP address of the load balancer to become available", id) { |lb| ip_address_ready?(lb) }
  end

  private def wait_for_load_balancer(description : String, id : Int32? = nil, & : Hetzner::LoadBalancer -> Bool) : Hetzner::LoadBalancer
    deadline = Time.monotonic + 5.minutes
    attempts = 0
    consecutive_misses = 0
    consecutive_failures = 0

    loop do
      attempts += 1
      fetched, load_balancer = fetch_load_balancer(id)

      if load_balancer
        consecutive_misses = 0
        consecutive_failures = 0
        break load_balancer if yield(load_balancer)
      elsif fetched
        consecutive_failures = 0
        # Only an uninterrupted run of successful listings that do not include the load balancer
        # counts as it being gone; failed probes are transient API errors.
        consecutive_misses += 1

        if consecutive_misses >= 30
          STDERR.puts "[#{default_log_prefix}] The load balancer could no longer be found while waiting for #{description}"
          raise "The load balancer could no longer be found while waiting for #{description}"
        end
      else
        consecutive_misses = 0
        consecutive_failures += 1

        if consecutive_failures % 10 == 0
          STDERR.puts "[#{default_log_prefix}] The load balancer state could not be fetched for a while (#{last_fetch_failure}); still retrying..."
        end
      end

      # Probes can block well beyond the 1 second sleep (client-side retries and rate limiting),
      # so the deadline is only honored after a minimum number of actual probes.
      if attempts >= 30 && Time.monotonic > deadline
        failure_details = last_fetch_failure ? " (last fetch failure: #{last_fetch_failure})" : ""
        STDERR.puts "[#{default_log_prefix}] Timed out waiting for #{description}#{failure_details}"
        raise "Timed out waiting for #{description}"
      end

      sleep 1.seconds
    end
  end

  # Single non-retried state probe used by the polling waits and the action idempotency checks.
  # Returns {fetched successfully, load balancer}: a failed probe ({false, nil}) is a transient
  # API error, while {true, nil} means the load balancer genuinely no longer exists. When an id
  # is given it must match too, so that probes for a specific load balancer are not satisfied
  # by a same-named replacement.
  private def fetch_load_balancer(id : Int32? = nil) : {Bool, Hetzner::LoadBalancer?}
    success, response = hetzner_client.get("/load_balancers", {:name => load_balancer_name})

    unless success
      self.last_fetch_failure = response.to_s[0, 200].presence || "request failed with an empty response"
      return {false, nil}
    end

    self.last_fetch_failure = nil
    {true, LoadBalancersList.from_json(response).load_balancers.find { |load_balancer| load_balancer.name == load_balancer_name && (id.nil? || load_balancer.id == id) }}
  rescue ex : IO::Error | OpenSSL::SSL::Error | JSON::ParseException
    self.last_fetch_failure = ex.message.try(&.presence) || ex.class.name
    {false, nil}
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
        master_target_params(use_private_ip: private_network_enabled),
      ],
    }

    config = config.merge({:network => network_id}) if private_network_enabled

    config
  end

  private def default_log_prefix
    "API Load balancer"
  end
end
