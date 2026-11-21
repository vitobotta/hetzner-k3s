require "../client"
require "../network"
require "../ssh_key"
require "../placement_group"
require "./cloud_init_generator"
require "./find"
require "../../kubernetes/util"
require "../../util"
require "../../util/shell"
require "../../util/ssh"

class Hetzner::Instance::Create
  include Util
  include Util::Shell
  include Kubernetes::Util

  INITIAL_DELAY =  1 # 1 second
  MAX_DELAY     = 60

  # The delay doubles up to MAX_DELAY. The exponent is capped because nothing bounds the number
  # of attempts: 2 ** 31 overflows Int32, and with a 60 second cap that is about an hour of
  # retries away, which a sold out server type reaches.
  def self.retry_delay_seconds(attempts : Int32) : Int64
    exponent = (attempts - 1).clamp(0, 6)
    [INITIAL_DELAY.to_i64 * (2_i64 ** exponent), MAX_DELAY.to_i64].min
  end

  # Hetzner answers a permanent rejection with this code, and no amount of retrying fixes it.
  # Parsed rather than matched against the body text, so pretty printing or the code appearing
  # inside a message cannot change the verdict.
  def self.invalid_input?(response : String) : Bool
    error = JSON.parse(response).as_h?.try(&.["error"]?).try(&.as_h?)
    return false unless error
    error["code"]?.try(&.as_s?) == "invalid_input"
  rescue JSON::ParseException
    false
  end

  # Bounds so a stuck Hetzner action reports an error instead of looping forever with no output.
  MAX_POWER_ON_ATTEMPTS = 30
  MAX_ATTACH_ATTEMPTS   = 30
  READINESS_TIMEOUT     = 20.minutes
  READINESS_POLL        = 10.seconds

  # Nodes take longer to become reachable via SSH when they first need to
  # install Tailscale and register with the tailnet during cloud-init.
  TAILSCALE_SSH_WAIT_ATTEMPTS = 60

  getter instance_name : String

  # Bounds and pacing, exposed so specs do not have to wait minutes.
  property max_power_on_attempts : Int32 = MAX_POWER_ON_ATTEMPTS
  property max_attach_attempts : Int32 = MAX_ATTACH_ATTEMPTS
  property readiness_timeout : Time::Span = READINESS_TIMEOUT
  property readiness_poll : Time::Span = READINESS_POLL

  private getter settings : Configuration::Main
  private getter legacy_instance_name : String
  private getter hetzner_client : Hetzner::Client
  private getter cluster_name : String
  private getter instance_type : String
  private getter image : String | Int64
  private getter location : String
  private getter ssh_key : Hetzner::SSHKey
  private getter network : Hetzner::Network?
  private getter enable_public_net_ipv4 : Bool
  private getter enable_public_net_ipv6 : Bool
  private getter additional_packages : Array(String)
  private getter additional_pre_k3s_commands : Array(String)
  private getter additional_post_k3s_commands : Array(String)
  private getter snapshot_os : String
  private getter ssh : Configuration::Models::NetworkingConfig::SSH
  private getter mutex : Mutex
  private getter ssh_client : Util::SSH do
    Util::SSH.new(ssh.private_key_path, ssh.public_key_path, ssh.use_private_ip,
      tailscale_hostname_suffix: settings.networking.tailscale.ssh_hostname_suffix)
  end
  property instance_existed : Bool = false
  private property powering_on_count : Int32 = 0
  private property attaching_to_network_count : Int32 = 0

  def initialize(
    @settings,
    @hetzner_client,
    @mutex,
    @legacy_instance_name,
    @instance_name,
    @instance_type,
    @image,
    @ssh_key,
    @network,
    @additional_packages = [] of String,
    @additional_pre_k3s_commands = [] of String,
    @additional_post_k3s_commands = [] of String,
    @location = "fsn1",
    @grow_root_partition_automatically = true,
    @placement_group : Hetzner::PlacementGroup? = nil
  )
    @cluster_name = settings.cluster_name
    @snapshot_os = settings.snapshot_os
    @ssh = settings.networking.ssh
    @enable_public_net_ipv4 = settings.networking.public_network.ipv4
    @enable_public_net_ipv6 = settings.networking.public_network.ipv6
  end

  def run
    instance = find_instance

    return handle_existing_instance(instance) if instance

    instance = create_instance
    log_line "...instance #{instance_name} created"
    instance
  end

  def self.cloud_init(settings, ssh_port = 22, snapshot_os = "default", additional_packages = [] of String, additional_pre_k3s_commands = [] of String, additional_post_k3s_commands = [] of String, init_commands = [] of String, grow_root_partition_automatically = true)
    CloudInitGenerator.new(
      settings: settings,
      ssh_port: ssh_port,
      snapshot_os: snapshot_os,
      additional_packages: additional_packages,
      additional_pre_k3s_commands: additional_pre_k3s_commands,
      additional_post_k3s_commands: additional_post_k3s_commands,
      init_commands: init_commands,
      grow_root_partition_automatically: grow_root_partition_automatically
    ).generate
  end

  private def create_instance
    attempts = 0

    loop do
      attempts += 1
      log_line "Creating instance #{instance_name} (attempt #{attempts})..."

      sleep rand(3001).milliseconds

      success, response = hetzner_client.post("/servers", instance_config)

      if success
        break
      else
        log_line "Creating instance #{instance_name} failed: #{response}"

        if self.class.invalid_input?(response)
          log_line "Aborting: Hetzner API rejected the request as invalid input, retrying will not help.\n#{response}"
          log_line "Hint: if the error is \"unsupported location for server type\", the server type may not be available in the target location. Common causes: (1) the server type is not offered in that datacenter, (2) the private network's zone does not cover the server's location (e.g. an eu-central network cannot host servers in ash/hil). See the README for details."
          exit 1
        end

        delay = self.class.retry_delay_seconds(attempts)
        log_line "Waiting #{delay} seconds before retry..."
        sleep delay.seconds
      end
    end

    ensure_instance_is_ready
  end

  private def handle_existing_instance(instance)
    @instance_name = instance.name
    @instance_existed = true
    ensure_instance_is_ready
  end

  private def ensure_instance_is_ready
    ready = false
    self.powering_on_count = 0
    self.attaching_to_network_count = 0
    started = Time.monotonic

    until ready
      if Time.monotonic - started > readiness_timeout
        raise "Instance #{instance_name} did not become ready within #{readiness_timeout.total_minutes.to_i} minutes"
      end

      sleep readiness_poll if !instance_existed && private_network_enabled?

      instance = find_instance
      next unless instance

      log_line "Instance status: #{instance.status}"

      next unless powered_on?(instance)

      sleep readiness_poll / 2

      next unless attached_to_network?(instance)

      ssh_client.wait_for_instance instance, ssh.port, ssh.use_agent, "echo ready", "ready", ssh_wait_attempts
      ready = true
    end

    instance
  end

  private def powered_on?(instance)
    return true unless needs_powering_on?(instance)

    raise "Instance #{instance_name} did not reach the running state after #{max_power_on_attempts} power on attempts" if powering_on_count >= max_power_on_attempts

    power_on_instance(instance)

    false
  end

  private def attached_to_network?(instance)
    return true unless needs_attaching_to_private_network?(instance)

    raise "Instance #{instance_name} was not attached to the private network after #{max_attach_attempts} attempts" if attaching_to_network_count >= max_attach_attempts

    attach_instance_to_network(instance)

    false
  end

  private def private_network_enabled?
    settings.networking.private_network.enabled
  end

  private def ssh_wait_attempts
    settings.networking.tailscale.enabled ? TAILSCALE_SSH_WAIT_ATTEMPTS : Util::SSH::DEFAULT_MAX_ATTEMPTS
  end

  private def needs_powering_on?(instance)
    instance.status != "running" && private_network_enabled?
  end

  private def needs_attaching_to_private_network?(instance)
    private_network_enabled? && !instance.try(&.private_ip_address)
  end

  private def power_on_instance(instance)
    self.powering_on_count += 1

    log_line "Powering on instance (attempt #{powering_on_count})"
    success, response = hetzner_client.post("/servers/#{instance.id}/actions/poweron", {} of String => String)
    log_line "Power on request failed: #{response}" unless success
    log_line "Waiting for instance to be powered on..."
  end

  private def attach_instance_to_network(instance)
    self.attaching_to_network_count += 1

    mutex.synchronize do
      log_line "Attaching instance to network (attempt #{attaching_to_network_count})"
      success, response = hetzner_client.post("/servers/#{instance.id}/actions/attach_to_network", {:network => network.not_nil!.id})
      log_line "Attach to network request failed: #{response}" unless success
      log_line "Waiting for instance to be attached to the network..."
    end
  end

  private def instance_config
    user_data = Hetzner::Instance::Create.cloud_init(settings, ssh.port, snapshot_os, additional_packages, additional_pre_k3s_commands, additional_post_k3s_commands, [] of String, @grow_root_partition_automatically)

    base_config = {
      :name       => instance_name,
      :location   => location,
      :image      => image,
      :public_net => {
        :enable_ipv4 => enable_public_net_ipv4,
        :enable_ipv6 => enable_public_net_ipv6,
      },
      :server_type => instance_type,
      :ssh_keys    => [
        ssh_key.id,
      ],
      :user_data => user_data,
      :labels    => {
        :cluster => cluster_name,
        :role    => (instance_name =~ /master/ ? "master" : "worker"),
      },
      :start_after_create => true,
    }

    network = @network
    base_config = base_config.merge({:networks => [network.id]}) unless network.nil?

    pg = @placement_group
    base_config = base_config.merge({:placement_group => pg.id}) if pg

    base_config
  end

  private def default_log_prefix
    "Instance #{instance_name}"
  end

  private def build_kubectl_command(instance_name)
    %(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}{"\\n"}{.items[0].status.addresses[?(@.type=="ExternalIP")].address}' --field-selector metadata.name=#{instance_name} 2>/dev/null)
  end

  private def initialize_instance(instance_name, internal_ip, external_ip)
    Hetzner::Instance.new(
      id: Random::Secure.rand(Int32::MIN..Int32::MAX),
      status: "running",
      instance_name: instance_name,
      internal_ip: internal_ip,
      external_ip: external_ip
    )
  end

  private def wait_for_ssh_response(instance)
    result = ssh_client.wait_for_instance(instance, ssh.port, ssh.use_agent, "echo ready", "ready", ssh_wait_attempts)
    result == "ready"
  end

  private def find_instance_with_kubectl(instance_name)
    return nil unless api_server_ready?(settings.kubeconfig_path)

    command = build_kubectl_command(instance_name)
    result = run_shell_command(command, settings.kubeconfig_path, settings.hetzner_token, print_output: false, abort_on_error: false)

    return nil unless result.success?

    internal_ip, external_ip = result.output.split("\n")
    external_ip ||= internal_ip

    return nil if internal_ip.blank? && external_ip.blank?

    instance = initialize_instance(instance_name, internal_ip, external_ip)
    wait_for_ssh_response(instance) ? instance : nil
  end

  private def find_instance_via_api(instance_name)
    instance_finder = Hetzner::Instance::Find.new(settings, hetzner_client, instance_name)
    instance = instance_finder.run
  end

  private def has_legacy_instance_name?
    legacy_instance_name != instance_name
  end

  private def find_instance_by_name(name)
    find_instance_with_kubectl(name) || find_instance_via_api(name)
  end

  private def find_instance
    instance = find_instance_by_name(legacy_instance_name) if has_legacy_instance_name?
    instance ||= find_instance_by_name(instance_name)

    instance
  end
end
