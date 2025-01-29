require "crinja"
require "../client"
require "../ssh_key"
require "../network"
require "../placement_group"
require "./find"
require "../../util"
require "../../util/ssh"
require "../../util/shell"
require "../../kubernetes/util"


class Hetzner::Instance::Create
  include Util
  include Util::Shell
  include Kubernetes::Util

  CLOUD_INIT_YAML = {{ read_file("#{__DIR__}/../../../templates/cloud_init.yaml") }}
  INITIAL_DELAY = 1     # 1 second
  MAX_DELAY = 60

  private getter settings : Configuration::Main
  private getter legacy_instance_name : String
  getter instance_name : String
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
  private getter additional_post_create_commands : Array(String)
  private getter instance_finder : Hetzner::Instance::Find?
  private getter snapshot_os : String
  private getter ssh : Configuration::NetworkingComponents::SSH
  private getter settings : Configuration::Main
  private getter private_ssh_key_path : String
  private getter public_ssh_key_path : String
  private getter mutex : Mutex
  private getter ssh_client : Util::SSH do
    Util::SSH.new(ssh.private_key_path, ssh.public_key_path)
  end
  private getter instance_existed : Bool = false

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
      @placement_group : Hetzner::PlacementGroup? = nil,
      @additional_packages = [] of String,
      @additional_post_create_commands = [] of String,
      @location = ""
    )

    @cluster_name = settings.cluster_name
    @snapshot_os = settings.snapshot_os
    @location = settings.masters_pool.location if location.empty?
    @ssh = settings.networking.ssh
    @enable_public_net_ipv4 = settings.networking.public_network.ipv4
    @enable_public_net_ipv6 = settings.networking.public_network.ipv6
    @private_ssh_key_path = settings.networking.ssh.private_key_path
    @public_ssh_key_path = settings.networking.ssh.public_key_path
  end

  def run
    instance = find_instance

    if instance
      @instance_name = instance.name
      @instance_existed = true
      ensure_instance_is_ready
    else
      instance = create_instance
      log_line "...instance #{instance_name} created"
    end

    instance.not_nil!
  end

  def self.cloud_init(settings, ssh_port = 22, snapshot_os = "default", additional_packages = [] of String, additional_post_create_commands = [] of String, init_commands = [] of String)
    Crinja.render(CLOUD_INIT_YAML, {
      packages_str: generate_packages_str(snapshot_os, additional_packages),
      post_create_commands_str: generate_post_create_commands_str(snapshot_os, additional_post_create_commands, init_commands),
      eth1_str: eth1(snapshot_os),
      growpart_str: growpart(snapshot_os),
      ssh_port: ssh_port
    })
  end

  def self.growpart(snapshot_os)
    snapshot_os == "microos" ? <<-YAML
    growpart:
      devices: ["/var"]
    YAML
    : ""
  end

  def self.eth1(snapshot_os)
    snapshot_os == "microos" ? <<-YAML
    - content: |
        BOOTPROTO='dhcp'
        STARTMODE='auto'
      path: /etc/sysconfig/network/ifcfg-eth1
    YAML
    : ""
  end

  def self.mandatory_post_create_commands
    [
      "hostnamectl set-hostname $(curl http://169.254.169.254/hetzner/v1/metadata/hostname)",
      "update-crypto-policies --set DEFAULT:SHA1 || true",
      "/etc/configure-ssh.sh",
      "echo \"nameserver 8.8.8.8\" > /etc/k8s-resolv.conf"
    ]
  end

  def self.generate_post_create_commands_str(snapshot_os, additional_post_create_commands, init_commands)
    post_create_commands = mandatory_post_create_commands.dup

    add_microos_commands(post_create_commands) if snapshot_os == "microos"

    formatted_additional_commands = format_additional_commands(additional_post_create_commands)

    combined_commands = [post_create_commands, init_commands, formatted_additional_commands].flatten

    "- #{combined_commands.join("\n- ")}"
  end

  def self.add_microos_commands(post_create_commands)
    post_create_commands.concat(microos_commands)
  end

  def self.format_additional_commands(commands)
    commands.map do |command|
      command.includes?("\n") ? format_multiline_command(command) : command
    end
  end

  def self.format_multiline_command(command)
    lines = ["|"]
    command.split("\n").each { |line| lines << "  #{line}" }
    lines.join("\n")
  end

  def self.generate_packages_str(snapshot_os, additional_packages)
    base_packages = %w[fail2ban]
    wireguard_package = snapshot_os == "microos" ? "wireguard-tools" : "wireguard"
    all_packages = base_packages + [wireguard_package] + additional_packages
    "'#{all_packages.join("', '")}'"
  end

  def self.microos_commands
    [
      "btrfs filesystem resize max /var",
      "sed -i 's/NETCONFIG_DNS_STATIC_SERVERS=\"\"/NETCONFIG_DNS_STATIC_SERVERS=\"1.1.1.1 1.0.0.1\"/g' /etc/sysconfig/network/config",
      "sed -i 's/#SystemMaxUse=/SystemMaxUse=3G/g' /etc/systemd/journald.conf",
      "sed -i 's/#MaxRetentionSec=/MaxRetentionSec=1week/g' /etc/systemd/journald.conf",
      "sed -i 's/NUMBER_LIMIT=\"2-10\"/NUMBER_LIMIT=\"4\"/g' /etc/snapper/configs/root",
      "sed -i 's/NUMBER_LIMIT_IMPORTANT=\"4-10\"/NUMBER_LIMIT_IMPORTANT=\"3\"/g' /etc/snapper/configs/root",
      "sed -i 's/NETCONFIG_NIS_SETDOMAINNAME=\"yes\"/NETCONFIG_NIS_SETDOMAINNAME=\"no\"/g' /etc/sysconfig/network/config",
      "sed -i 's/DHCLIENT_SET_HOSTNAME=\"yes\"/DHCLIENT_SET_HOSTNAME=\"no\"/g' /etc/sysconfig/network/dhcp"
    ]
  end

  private def create_instance
    attempts = 0

    loop do
      attempts += 1
      log_line "Creating instance #{instance_name} (attempt #{attempts})..."
      success, response = hetzner_client.post("/servers", instance_config)

      if success
        break
      else
        log_line "Creating instance #{instance_name} failed: #{response}"
        delay = [INITIAL_DELAY * (2 ** (attempts - 1)), MAX_DELAY].min
        log_line "Waiting #{delay} seconds before retry..."
        sleep delay.seconds
      end
    end

    ensure_instance_is_ready
  end

  private def ensure_instance_is_ready
    ready = false
    powering_on_count = 0
    attaching_to_network_count = 0

    until ready
      sleep 10.seconds if !instance_existed && private_network_enabled?

      instance = find_instance
      next unless instance

      log_line "Instance status: #{instance.status}"

      next unless powered_on?(instance, powering_on_count)

      sleep 5.seconds

      next unless attached_to_network?(instance, attaching_to_network_count)

      ssh_client.wait_for_instance instance, ssh.port, ssh.use_agent, "echo ready", "ready"
      ready = true
    end

    instance
  end

  private def powered_on?(instance, powering_on_count)
    return true unless needs_powering_on?(instance)

    power_on_instance(instance, powering_on_count)

    false
  end

  private def attached_to_network?(instance, attaching_to_network_count)
    return true unless needs_attaching_to_private_network?(instance)

    attach_instance_to_network(instance, attaching_to_network_count)

    false
  end

  private def private_network_enabled?
    settings.networking.private_network.enabled
  end

  private def needs_powering_on?(instance)
    instance.status != "running" && private_network_enabled?
  end

  private def needs_attaching_to_private_network?(instance)
    private_network_enabled? && !instance.try(&.private_ip_address)
  end

  private def power_on_instance(instance, powering_on_count)
    powering_on_count += 1

    log_line "Powering on instance (attempt #{powering_on_count})"
    hetzner_client.post("/servers/#{instance.id}/actions/poweron", {} of String => String)
    log_line "Waiting for instance to be powered on..."
  end

  private def attach_instance_to_network(instance, attaching_to_network_count)
    attaching_to_network_count += 1

    mutex.synchronize do
      log_line "Attaching instance to network (attempt #{attaching_to_network_count})"
      hetzner_client.post("/servers/#{instance.id}/actions/attach_to_network", { :network => network.not_nil!.id })
      log_line "Waiting for instance to be attached to the network..."
    end
  end

  private def instance_config
    user_data = Hetzner::Instance::Create.cloud_init(settings, ssh.port, snapshot_os, additional_packages, additional_post_create_commands)

    base_config = {
      :name => instance_name,
      :location => location,
      :image => image,
      :public_net => {
        :enable_ipv4 => enable_public_net_ipv4,
        :enable_ipv6 => enable_public_net_ipv6,
      },
      :server_type => instance_type,
      :ssh_keys => [
        ssh_key.id
      ],
      :user_data => user_data,
      :labels => {
        :cluster => cluster_name,
        :role => (instance_name =~ /master/ ? "master" : "worker")
      },
      :start_after_create => true
    }

    placement_group = @placement_group
    network = @network

    base_config = base_config.merge({ :placement_group => placement_group.id }) unless placement_group.nil?
    base_config = base_config.merge({ :networks => [network.id] }) unless network.nil?

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
    result = ssh_client.wait_for_instance(instance, ssh.port, ssh.use_agent, "echo ready", "ready")
    result == "ready"
  end

  private def find_instance_with_kubectl(instance_name)
    return nil unless api_server_ready?(settings.kubeconfig_path)

    command = build_kubectl_command(instance_name)

    debug = ENV.fetch("DEBUG", "false") == "true"

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
