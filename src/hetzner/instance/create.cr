require "crinja"
require "../client"
require "../ssh_key"
require "../network"
require "../placement_group"
require "./find"
require "../../util"
require "../../util/ssh"

class Hetzner::Instance::Create
  include Util

  CLOUD_INIT_YAML = {{ read_file("#{__DIR__}/../../../templates/cloud_init.yaml") }}

  private getter settings : Configuration::Main
  private getter instance_name : String
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
  private getter instance_finder : Hetzner::Instance::Find
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

    @instance_finder = Hetzner::Instance::Find.new(@hetzner_client, @instance_name)
  end

  def run
    instance = instance_finder.run

    if instance
      @instance_existed = true
      log_line "Instance #{instance_name} already exists, skipping create"
      ensure_instance_is_ready
    else
      instance = create_instance

      log_line "...instance #{instance_name} created"
    end

    instance.not_nil!
  end

  private def create_instance
    attempts = 0

    loop do
      attempts += 1
      log_line "Creating instance #{instance_name} (attempt #{attempts})..."
      success, response = hetzner_client.post("/servers", instance_config)
      puts response unless success
      break if success
    end

    ensure_instance_is_ready
  end

  private def ensure_instance_is_ready
    ready = false
    powering_on_count = 0
    attaching_to_network_count = 0

    until ready
      unless instance_existed
        sleep 10
      end

      instance = instance_finder.run

      next unless instance

      log_line "Instance status: #{instance.status}"

      unless instance.status == "running"
        powering_on_count += 1
        power_on_instance(instance, powering_on_count)
        next
      end

      if settings.networking.private_network.enabled && !instance.try(&.private_ip_address)
        attaching_to_network_count += 1
        attach_instance_to_network(instance, attaching_to_network_count)
        next
      end

      ssh_client.wait_for_instance instance, ssh.port, ssh.use_agent, "echo ready", "ready"
      ready = true
    end

    instance
  end

  private def power_on_instance(instance, powering_on_count)
    log_line "Powering on instance (attempt #{powering_on_count})"
    hetzner_client.post("/servers/#{instance.id}/actions/poweron", {} of String => String)
    log_line "Waiting for instance to be powered on..."
  end

  private def attach_instance_to_network(instance, attaching_to_network_count)
    mutex.synchronize do
      log_line "Attaching instance to network (attempt #{attaching_to_network_count})"
      hetzner_client.post("/servers/#{instance.id}/actions/attach_to_network", { network: network.not_nil!.id })
      log_line "Waiting for instance to be attached to the network..."
    end
  end

  private def instance_config
    user_data = Hetzner::Instance::Create.cloud_init(settings, ssh.port, snapshot_os, additional_packages, additional_post_create_commands)

    base_config = {
      name: instance_name,
      location: location,
      image: image,
      public_net: {
        enable_ipv4: enable_public_net_ipv4,
        enable_ipv6: enable_public_net_ipv6,
      },
      server_type: instance_type,
      ssh_keys: [
        ssh_key.id
      ],
      user_data: user_data,
      labels: {
        cluster: cluster_name,
        role: (instance_name =~ /master/ ? "master" : "worker")
      },
      start_after_create: false
    }

    placement_group = @placement_group

    if placement_group.nil?
      base_config
    else
      base_config.merge({ placement_group: placement_group.id })
    end
  end

  def self.cloud_init(settings, ssh_port = 22, snapshot_os = "default", additional_packages = [] of String, additional_post_create_commands = [] of String, final_commands = [] of String)
    Crinja.render(CLOUD_INIT_YAML, {
      packages_str: generate_packages_str(snapshot_os, additional_packages),
      post_create_commands_str: generate_post_create_commands_str(snapshot_os, additional_post_create_commands, final_commands),
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
      "echo \"nameserver 8.8.8.8\" > /etc/k8s-resolv.conf"
    ]
  end

  def self.generate_post_create_commands_str(snapshot_os, additional_post_create_commands, final_commands)
    post_create_commands = mandatory_post_create_commands

    if snapshot_os == "microos"
      post_create_commands += microos_commands
    end

    post_create_commands += additional_post_create_commands + final_commands

    "- #{post_create_commands.join("\n- ")}"
  end

  def self.generate_packages_str(snapshot_os, additional_packages)
    packages = %w[fail2ban]
    wireguard = snapshot_os == "microos" ? "wireguard-tools" : "wireguard"
    packages << wireguard
    packages += additional_packages
    "'#{packages.join("', '")}'"
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

  private def default_log_prefix
    "Instance #{instance_name}"
  end
end
