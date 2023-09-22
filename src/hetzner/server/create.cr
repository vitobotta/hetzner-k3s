require "crinja"
require "../client"
require "../ssh_key"
require "../firewall"
require "../network"
require "../placement_group"
require "./find"

class Hetzner::Server::Create
  CLOUD_INIT_YAML = {{ read_file("#{__DIR__}/../../../templates/cloud_init.yaml") }}

  getter hetzner_client : Hetzner::Client
  getter cluster_name : String
  getter server_name : String
  getter instance_type : String
  getter image : String | Int64
  getter location : String
  getter ssh_key : Hetzner::SSHKey
  getter firewall : Hetzner::Firewall
  getter placement_group : Hetzner::PlacementGroup
  getter network : Hetzner::Network
  getter enable_public_net_ipv4 : Bool
  getter enable_public_net_ipv6 : Bool
  getter additional_packages : Array(String)
  getter additional_post_create_commands : Array(String)
  getter server_finder : Hetzner::Server::Find
  getter snapshot_os : String
  getter ssh_port : Int32

  def initialize(
      @hetzner_client,
      @cluster_name,
      @server_name,
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
      @additional_packages = [] of String,
      @additional_post_create_commands = [] of String
    )

    @server_finder = Hetzner::Server::Find.new(@hetzner_client, @server_name)
  end

  def run
    server = server_finder.run

    if server
      puts "Server #{server_name} already exists, skipping."
    else
      puts "Creating server #{server_name}..."

      hetzner_client.post("/servers", server_config)
      server = wait_for_server_creation

      puts "...server #{server_name} created."
    end

    server.not_nil!

  rescue ex : Crest::RequestFailed
    STDERR.puts "Failed to create server: #{ex.message}"
    STDERR.puts ex.response

    exit 1
  end

  private def wait_for_server_creation
    loop do
      server = server_finder.run
      return server if server.try(&.private_ip_address)
      sleep 1
    end
  end

  private def server_config
    user_data = Hetzner::Server::Create.cloud_init(ssh_port, snapshot_os, additional_packages, additional_post_create_commands)

    {
      name: server_name,
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
        role: (server_name =~ /master/ ? "master" : "worker")
      },
      placement_group: placement_group.id
    }
  end

  def self.cloud_init(ssh_port = 22, snapshot_os = "default", additional_packages = [] of String, additional_post_create_commands = [] of String, final_commands = [] of String)
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
end
