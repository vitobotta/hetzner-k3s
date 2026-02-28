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
      ssh_files:                              ssh_files,
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
    commands = [
      "hostnamectl set-hostname $(curl http://169.254.169.254/hetzner/v1/metadata/hostname)",
      "update-crypto-policies --set DEFAULT:SHA1 || true",
      "/etc/configure_ssh.sh",
      "echo \"nameserver 8.8.8.8\" > /etc/k8s-resolv.conf",
    ]

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
    formatted_post_commands = format_additional_commands(@additional_post_k3s_commands)

    script_commands = Array(String).new
    @init_commands.each_with_index do |cmd, index|
      script_commands << "/etc/init-#{index}.sh"
    end

    combined_commands = [formatted_pre_commands, mandatory_commands, script_commands, formatted_post_commands].flatten

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
