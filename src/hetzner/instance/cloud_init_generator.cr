require "crinja"
require "compress/gzip"
require "base64"

class Hetzner::Instance::CloudInitGenerator
  CLOUD_INIT_YAML = {{ read_file("#{__DIR__}/../../../templates/cloud_init.yaml") }}

  FIREWALL_SCRIPT  = {{ read_file("#{__DIR__}/../../../templates/firewall/firewall.sh") }}
  FIREWALL_SERVICE = {{ read_file("#{__DIR__}/../../../templates/firewall/firewall.service") }}
  FIREWALL_STATUS  = {{ read_file("#{__DIR__}/../../../templates/firewall/firewall_status.sh") }}

  SSH_LISTEN_CONF          = {{ read_file("#{__DIR__}/../../../templates/ssh/listen.conf") }}
  SSH_CONFIGURATION_SCRIPT = {{ read_file("#{__DIR__}/../../../templates/ssh/configure_ssh.sh") }}

  TAILSCALE_NFTABLES_FIX_SCRIPT  = {{ read_file("#{__DIR__}/../../../templates/tailscale/tailscale_nftables_fix.sh") }}
  TAILSCALE_NFTABLES_FIX_SERVICE = {{ read_file("#{__DIR__}/../../../templates/tailscale/tailscale_nftables_fix.service") }}

  CONFIGURE_DNS_SCRIPT = {{ read_file("#{__DIR__}/../../../templates/configure_dns.sh") }}

  def initialize(
    @settings : Configuration::Main,
    @ssh_port : Int32,
    @snapshot_os : String,
    @additional_packages : Array(String),
    @additional_pre_k3s_commands : Array(String),
    @additional_post_k3s_commands : Array(String),
    @init_commands : Array(String),
    @grow_root_partition_automatically : Bool
  )
  end

  def generate
    Crinja.render(CLOUD_INIT_YAML, {
      packages_str:                           generate_packages_str,
      post_create_commands_str:               generate_post_create_commands_str,
      eth1_str:                               eth1,
      firewall_files:                         firewall_files,
      dns_files:                              dns_files,
      ssh_files:                              ssh_files,
      tailscale_files:                        tailscale_files,
      init_files:                             init_file_content,
      allowed_kubernetes_api_networks_config: allowed_kubernetes_api_networks_config,
      allowed_ssh_networks_config:            allowed_ssh_networks_config,
      growpart_str:                           growpart,
      growroot_disabled_file:                 growroot_disabled_file,
      ssh_port:                               @ssh_port,
    })
  end

  private def encode(content)
    io = IO::Memory.new
    Compress::Gzip::Writer.open(io) do |gzip|
      gzip.write(content.to_slice)
    end
    Base64.strict_encode(io.to_s)
  end

  private def format_file_content(content)
    "|\n    #{encode(content).gsub("\n", "\n    ")}"
  end

  private def allowed_kubernetes_api_networks_config
    format_file_content(@settings.networking.allowed_networks.api.join("\n"))
  end

  private def allowed_ssh_networks_config
    format_file_content(@settings.networking.allowed_networks.ssh.join("\n"))
  end

  private def firewall_script
    script = Crinja.render(FIREWALL_SCRIPT, {
      hetzner_token:                @settings.hetzner_token,
      hetzner_ips_query_server_url: @settings.networking.public_network.hetzner_ips_query_server_url,
      ssh_port:                     @settings.networking.ssh.port,
      cluster_cidr:                 @settings.networking.cluster_cidr,
      service_cidr:                 @settings.networking.service_cidr,
      node_port_range_iptables:     @settings.networking.node_port_range_iptables,
      node_port_firewall_enabled:   @settings.networking.node_port_firewall_enabled,
    })
    format_file_content(script)
  end

  private def firewall_service
    format_file_content(FIREWALL_SERVICE)
  end

  private def firewall_status_script
    script = Crinja.render(FIREWALL_STATUS, {
      ssh_port: @settings.networking.ssh.port,
    })
    format_file_content(script)
  end

  private def firewall_files
    return "" if @settings.networking.private_network.enabled || !@settings.networking.public_network.use_local_firewall

    <<-YAML
    - content: #{allowed_kubernetes_api_networks_config}
      path: /etc/allowed-networks-kubernetes-api.conf
      encoding: gzip+base64
    - content: #{allowed_ssh_networks_config}
      path: /etc/allowed-networks-ssh.conf
      encoding: gzip+base64
    - path: /usr/local/bin/firewall.sh
      permissions: '0755'
      content: #{firewall_script}
      encoding: gzip+base64
    - path: /etc/systemd/system/firewall.service
      content: #{firewall_service}
      encoding: gzip+base64
    - path: /usr/local/bin/firewall-status
      permissions: '0755'
      content: #{firewall_status_script}
      encoding: gzip+base64
    YAML
  end

  private def ssh_listen_conf
    conf = Crinja.render(SSH_LISTEN_CONF, {
      ssh_port: @settings.networking.ssh.port,
    })
    format_file_content(conf)
  end

  private def ssh_configuration_script
    script = Crinja.render(SSH_CONFIGURATION_SCRIPT, {
      ssh_port: @settings.networking.ssh.port,
    })
    format_file_content(script)
  end

  private def ssh_files
    <<-YAML
    - content: #{ssh_listen_conf}
      path: /etc/systemd/system/ssh.socket.d/listen.conf
      encoding: gzip+base64
    - content: #{ssh_configuration_script}
      permissions: '0755'
      path: /etc/configure_ssh.sh
      encoding: gzip+base64
    YAML
  end

  private def dns_files
    return "" if @settings.networking.dns_servers.empty?

    <<-YAML
    - content: #{configure_dns_script}
      permissions: '0755'
      path: /usr/local/bin/configure-dns.sh
      encoding: gzip+base64
    YAML
  end

  private def configure_dns_script
    # Build a Python list literal using single quotes so the Crinja-rendered
    # value is valid Python without conflicting with outer shell quoting.
    servers_list = "[" + @settings.networking.dns_servers.map { |s| "'#{s}'" }.join(", ") + "]"
    script = Crinja.render(CONFIGURE_DNS_SCRIPT, {
      dns_servers_list: servers_list,
    })
    format_file_content(script)
  end

  private def tailscale_files
    return "" unless @settings.networking.ssh.use_tailscale

    auth_key = @settings.networking.ssh.tailscale_auth_key

    <<-YAML
    - content: |
        #{auth_key}
      path: /run/tailscale-authkey
      permissions: '0600'
    - content: #{tailscale_nftables_fix_script}
      permissions: '0755'
      path: /usr/local/bin/tailscale-nftables-fix.sh
      encoding: gzip+base64
    - content: #{tailscale_nftables_fix_service}
      path: /etc/systemd/system/tailscale-nftables-fix.service
      encoding: gzip+base64
    YAML
  end

  private def tailscale_nftables_fix_script
    format_file_content(TAILSCALE_NFTABLES_FIX_SCRIPT)
  end

  private def tailscale_nftables_fix_service
    format_file_content(TAILSCALE_NFTABLES_FIX_SERVICE)
  end

  private def growpart
    @snapshot_os == "microos" ? <<-YAML
    growpart:
      devices: ["/var"]
    YAML
 : ""
  end

  private def growroot_disabled_file
    return "" if @grow_root_partition_automatically

    <<-YAML
    - content: |
        true
      path: /etc/growroot-disabled
    YAML
  end

  private def eth1
    @snapshot_os == "microos" ? <<-YAML
    - content: |
        BOOTPROTO='dhcp'
        STARTMODE='auto'
      path: /etc/sysconfig/network/ifcfg-eth1
    YAML
 : ""
  end

  private def init_file_content
    return "" if @init_commands.empty?

    scripts = [] of String
    files = script_files
    files.each do |filename, content|
      script = <<-YAML
      - content: #{format_file_content(content)}
        path: #{filename}
        encoding: gzip+base64
        permissions: '0755'
      YAML

      scripts << script
    end

    scripts.join("\n")
  end

  private def script_files
    script_files = {} of String => String
    @init_commands.each_with_index do |cmd, index|
      filename = "/etc/init-#{index}.sh"
      script_files[filename] = cmd
    end
    script_files
  end

  private def mandatory_post_create_commands
    commands = [] of String

    commands << "/usr/local/bin/configure-dns.sh" unless @settings.networking.dns_servers.empty?

    commands << "hostnamectl set-hostname $(curl http://169.254.169.254/hetzner/v1/metadata/hostname)"

    if @settings.networking.ssh.use_tailscale
      commands << "curl -fsSL https://tailscale.com/install.sh | sh"
      commands << "tailscale up --authkey=$(cat /run/tailscale-authkey) --hostname=$(hostname) --accept-routes && rm -f /run/tailscale-authkey"

      # Disable Tailscale's built-in DNS so custom DNS servers (e.g. NAT64 resolvers)
      # can handle all queries. Without this, Tailscale's MagicDNS intercepts queries
      # and returns IPv4 addresses for domains like github.com, which IPv6-only nodes
      # cannot reach. Note: this means MagicDNS hostnames (node.tailnet.ts.net) will
      # only resolve via the Hetzner metadata API during provisioning.
      commands << "tailscale set --accept-dns=false"

      # Enable the nftables fix service to handle Tailscale's ts-input chain
      # dropping DNAT'd ClusterIP traffic on IPv6-only nodes with CGNAT addresses
      commands << "systemctl daemon-reload && systemctl enable --now tailscale-nftables-fix.service"
    end

    commands.concat([
      "/etc/configure_ssh.sh",
    ])

    if !@settings.networking.private_network.enabled && @settings.networking.public_network.use_local_firewall
      commands << "/usr/local/bin/firewall.sh setup"
      commands << "systemctl daemon-reload && systemctl enable --now firewall.service"
    end

    commands
  end

  private def generate_post_create_commands_str
    mandatory_commands = mandatory_post_create_commands.dup

    add_microos_commands(mandatory_commands) if @snapshot_os == "microos"

    formatted_pre_commands = format_additional_commands(@additional_pre_k3s_commands)
    formatted_mandatory_commands = format_additional_commands(mandatory_commands)
    formatted_post_commands = format_additional_commands(@additional_post_k3s_commands)

    script_commands = Array(String).new
    @init_commands.each_with_index do |cmd, index|
      script_commands << "/etc/init-#{index}.sh"
    end

    combined_commands = [formatted_pre_commands, formatted_mandatory_commands, script_commands, formatted_post_commands].flatten

    "- #{combined_commands.join("\n- ")}"
  end

  private def microos_commands
    [
      "btrfs filesystem resize max /var",
      "sed -i 's/NETCONFIG_DNS_STATIC_SERVERS=\"\"/NETCONFIG_DNS_STATIC_SERVERS=\"1.1.1.1 1.0.0.1\"/g' /etc/sysconfig/network/config",
      "sed -i 's/#SystemMaxUse=/SystemMaxUse=3G/g' /etc/systemd/journald.conf",
      "sed -i 's/#MaxRetentionSec=/MaxRetentionSec=1week/g' /etc/systemd/journald.conf",
      "sed -i 's/NUMBER_LIMIT=\"2-10\"/NUMBER_LIMIT=\"4\"/g' /etc/snapper/configs/root",
      "sed -i 's/NUMBER_LIMIT_IMPORTANT=\"4-10\"/NUMBER_LIMIT_IMPORTANT=\"3\"/g' /etc/snapper/configs/root",
      "sed -i 's/NETCONFIG_NIS_SETDOMAINNAME=\"yes\"/NETCONFIG_NIS_SETDOMAINNAME=\"no\"/g' /etc/sysconfig/network/config",
      "sed -i 's/DHCLIENT_SET_HOSTNAME=\"yes\"/DHCLIENT_SET_HOSTNAME=\"no\"/g' /etc/sysconfig/network/dhcp",
    ]
  end

  private def add_microos_commands(commands)
    commands.concat(microos_commands)
  end

  private def generate_packages_str
    base_packages = %w[fail2ban]
    wireguard_package = @snapshot_os == "microos" ? "wireguard-tools" : "wireguard"
    all_packages = base_packages + [wireguard_package] + @additional_packages
    "'#{all_packages.join("', '")}'"
  end

  private def format_additional_commands(commands)
    commands.map do |command|
      command.includes?("\n") ? format_multiline_command(command) : command
    end
  end

  private def format_multiline_command(command)
    lines = ["|"]
    command.split("\n").each { |line| lines << "  #{line}" }
    lines.join("\n")
  end
end
