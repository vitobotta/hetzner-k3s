require "../client"
require "../server"
require "../servers_list"

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
  end

  def run
    puts

    begin
      if server = find_server
        puts "Server #{server_name} already exists, skipping. \n".colorize(:light_gray)
      else
        puts "Creating server #{server_name}...".colorize(:light_gray)

        hetzner_client.post("/servers", server_config)

        puts "...server #{server_name} created.\n".colorize(:light_gray)

        server = find_server
      end

      server.not_nil!

    rescue ex : Crest::RequestFailed
      STDERR.puts "Failed to create server: #{ex.message}".colorize(:red)
      STDERR.puts ex.response

      exit 1
    end
  end

  private def find_server
    servers = ServersList.from_json(hetzner_client.get("/servers")).servers

    servers.find do |server|
      server.name == server_name
    end
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
      user_data: user_data,
      labels: {
        cluster: cluster_name,
        role: (server_name =~ /master/ ? "master" : "worker")
      },
      placement_group: placement_group.id
    }
  end

  private def user_data
    packages = %w[fail2ban wireguard]
    packages += additional_packages
    packages = "'#{packages.join("', '")}'"

    post_create_commands = [
      "crontab -l > /etc/cron_bkp",
      "echo '@reboot echo true > /etc/ready' >> /etc/cron_bkp",
      "crontab /etc/cron_bkp",
      "sed -i 's/[#]*PermitRootLogin yes/PermitRootLogin prohibit-password/g' /etc/ssh/sshd_config",
      "sed -i 's/[#]*PasswordAuthentication yes/PasswordAuthentication no/g' /etc/ssh/sshd_config",
      "systemctl restart sshd",
      "systemctl stop systemd-resolved",
      "systemctl disable systemd-resolved",
      "rm /etc/resolv.conf",
      "echo 'nameserver 1.1.1.1' > /etc/resolv.conf",
      "echo 'nameserver 1.0.0.1' >> /etc/resolv.conf"
    ]

    post_create_commands += additional_post_create_commands
    post_create_commands << "shutdown -r now" if post_create_commands.select { |command| /shutdown|reboot/ =~ command && /@reboot/ !~ command }.empty?
    post_create_commands = "  - #{post_create_commands.join("\n  - ")}"

    <<-YAML
      #cloud-config
      packages: [#{packages}]
      runcmd:
      #{post_create_commands}
    YAML
  end
end