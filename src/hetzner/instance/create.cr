require "crinja"
require "../client"
require "../ssh_key"
require "../firewall"
require "../network"
require "../placement_group"
require "./find"
require "../../util"
require "../../util/ssh"

class Hetzner::Instance::Create
  include Util

  CLOUD_INIT_YAML = {{ read_file("#{__DIR__}/../../../templates/cloud_init.yaml") }}

  private getter hetzner_client : Hetzner::Client
  private getter cluster_name : String
  private getter instance_name : String
  private getter instance_type : String
  private getter image : String | Int64
  private getter location : String
  private getter ssh_key : Hetzner::SSHKey
  private getter firewall : Hetzner::Firewall
  private getter placement_group : Hetzner::PlacementGroup
  private getter network : Hetzner::Network
  private getter enable_public_net_ipv4 : Bool
  private getter enable_public_net_ipv6 : Bool
  private getter additional_packages : Array(String)
  private getter additional_post_create_commands : Array(String)
  private getter instance_finder : Hetzner::Instance::Find
  private getter snapshot_os : String
  private getter ssh_port : Int32
  private getter settings : Configuration::Main
  private getter private_ssh_key_path : String
  private getter public_ssh_key_path : String
  private getter ssh : Util::SSH do
    Util::SSH.new(private_ssh_key_path, public_ssh_key_path)
  end

  def initialize(
      @settings,
      @hetzner_client,
      @cluster_name,
      @instance_name,
      @instance_type,
      @image,
      @snapshot_os,
      @location,
      @ssh_key,
      @firewall,
      @placement_group,
      @network,
      @enable_public_net_ipv4,
      @enable_public_net_ipv6,
      @ssh_port,
      @private_ssh_key_path,
      @public_ssh_key_path,
      @additional_packages = [] of String,
      @additional_post_create_commands = [] of String
    )

    @instance_finder = Hetzner::Instance::Find.new(@hetzner_client, @instance_name)
  end

  def run
    instance = instance_finder.run

    if instance
      log_line "Instance #{instance_name} already exists, skipping create"
      wait_for_instance_to_be_ready
    else
      log_line "Creating instance #{instance_name}..."

      hetzner_client.post("/servers", instance_config)
      instance = wait_for_instance_to_be_ready

      log_line "...instance #{instance_name} created"
    end

    instance.not_nil!

  rescue ex : Crest::RequestFailed
    STDERR.puts "[#{default_log_prefix}] Failed to create instance: #{ex.message}"
    exit 1
  end

  private def wait_for_instance_to_be_ready
    loop do
      instance = instance_finder.run

      if instance && instance.try(&.private_ip_address)
        ssh.wait_for_instance instance, settings.ssh_port, settings.use_ssh_agent, "echo ready", "ready"
        return instance
      end
      sleep 3
    end
  end

  private def instance_config
    user_data = Hetzner::Instance::Create.cloud_init(settings, ssh_port, snapshot_os, additional_packages, additional_post_create_commands)

    {
      name: instance_name,
      location: location,
      image: image,
      firewalls: [
        { firewall: firewall.id }
      ],
      networks: [
        network.id
      ],
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
      placement_group: placement_group.id
    }
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
      "update-crypto-policies --set DEFAULT:SHA1 || true"
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
