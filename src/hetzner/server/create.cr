require "../client"
require "../ssh_key"
require "../firewall"
require "../network"
require "../placement_group"
require "./find"

class Hetzner::Server::Create
  getter hetzner_client : Hetzner::Client
  getter cluster_name : String
  getter server_name : String
  getter instance_type : String
  getter image : String
  getter location : String
  getter ssh_key : Hetzner::SSHKey
  getter firewall : Hetzner::Firewall
  getter placement_group : Hetzner::PlacementGroup
  getter network : Hetzner::Network
  getter additional_packages : Array(String)
  getter additional_post_create_commands : Array(String)
  getter server_finder : Hetzner::Server::Find

  def initialize(
      @hetzner_client,
      @cluster_name,
      @server_name,
      @instance_type,
      @image,
      @location,
      @ssh_key,
      @firewall,
      @placement_group,
      @network,
      @additional_packages = [] of String,
      @additional_post_create_commands = [] of String
    )

    @server_finder = Hetzner::Server::Find.new(@hetzner_client, @server_name)
  end

  def run
    if server = server_finder.run
      puts "Server #{server_name} already exists, skipping."
    else
      puts "Creating server #{server_name}..."

      hetzner_client.post("/servers", server_config)
      server = server_finder.run

      while server.try(&.private_ip_address).nil?
        sleep 1
        server = server_finder.run
      end

      puts "...server #{server_name} created."

    end

    server.not_nil!

  rescue ex : Crest::RequestFailed
    STDERR.puts "Failed to create server: #{ex.message}"
    STDERR.puts ex.response

    exit 1
  end

  private def server_config
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
      server_type: instance_type,
      ssh_keys: [
        ssh_key.id
      ],
      user_data: Hetzner::Server::Create.cloud_init(additional_packages, additional_post_create_commands),
      labels: {
        cluster: cluster_name,
        role: (server_name =~ /master/ ? "master" : "worker")
      },
      placement_group: placement_group.id
    }
  end

  def self.cloud_init(additional_packages = [] of String, additional_post_create_commands = [] of String, final_commands = [] of String)
    snapshot_os = "microos"

    packages = %w[fail2ban]

    wireguard = case snapshot_os
    when "microos"
      "wireguard-tools"
    else
      "wireguard"
    end

    packages << wireguard

    packages += additional_packages
    packages = "'#{packages.join("', '")}'"

    # "echo '[Unit]' > /etc/systemd/system/mark-ready.service",
    # "echo 'Description=Mark node as ready job' >> /etc/systemd/system/mark-ready.service",
    # "echo '[Service]' >> /etc/systemd/system/mark-ready.service",
    # "echo 'Type=oneshot' >> /etc/systemd/system/mark-ready.service",
    # "echo 'ExecStart=/bin/bash -c \"echo true > /etc/ready\"' >> /etc/systemd/system/mark-ready.service",
    # "echo '[Unit]' > /etc/systemd/system/mark-ready.timer",
    # "echo 'Description=Mark node as ready' >> /etc/systemd/system/mark-ready.timer",
    # "echo '[Timer]' >> /etc/systemd/system/mark-ready.timer",
    # "echo 'OnBootSec=1s' >> /etc/systemd/system/mark-ready.timer",
    # "echo 'OnUnitActiveSec=1s' >> /etc/systemd/system/mark-ready.timer",
    # "echo '[Install]' >> /etc/systemd/system/mark-ready.timer",
    # "echo 'WantedBy=timers.target' >> /etc/systemd/system/mark-ready.timer",
    # "systemctl daemon-reload",
    # "systemctl enable mark-ready.timer"
    mandatory_post_create_commands = [
      "hostnamectl set-hostname $(curl http://169.254.169.254/hetzner/v1/metadata/hostname)",
    ]

    if snapshot_os == "microos"
      mandatory_post_create_commands += [
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

    post_create_commands = mandatory_post_create_commands
    post_create_commands += additional_post_create_commands
    post_create_commands += final_commands
    post_create_commands << "shutdown -r now" unless final_commands.empty?
    post_create_commands = "- #{post_create_commands.join("\n- ")}"

    growpart = case snapshot_os
    when "microos"
      <<-YAML
      growpart:
        devices: ["/var"]
      YAML
    else
      ""
    end

    eth1 = case snapshot_os
    when "microos"
      <<-YAML
      - content: |
          BOOTPROTO='dhcp'
          STARTMODE='auto'
        path: /etc/sysconfig/network/ifcfg-eth1
      YAML
    else
      ""
    end

    <<-YAML
    #cloud-config
    preserve_hostname: true

    write_files:
    #{eth1}

    - content: |
        PasswordAuthentication no
        X11Forwarding no
        MaxAuthTries 2
        AllowTcpForwarding no
        AllowAgentForwarding no
      path: /etc/ssh/sshd_config.d/ssh.conf

    #{growpart}

    packages: [#{packages}]

    runcmd:
    #{post_create_commands}

    YAML
  end
end
