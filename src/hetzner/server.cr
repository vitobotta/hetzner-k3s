require "./client"
require "./servers_list"
require "./public_net"

class Hetzner::Server
  include JSON::Serializable

  property id : Int32
  property name : String
  getter public_net : PublicNet?

  def ip_address
    public_net.try(&.ipv4).try(&.ip)
  end

  def self.create(
      hetzner_client,
      server_name,
      instance_type,
      image,
      location,
      ssh_key,
      firewall,
      placement_group,
      network,
      additional_packages = [] of String,
      additional_post_create_commands = [] of String
    )

    puts

    begin
      if server = find(hetzner_client, server_name)
        puts "Server #{server_name} already exists, skipping. \n"
      else
        puts "Creating server #{server_name}..."

        config = server_config(
          server_name,
          instance_type,
          image,
          location,
          ssh_key,
          firewall,
          placement_group,
          network,
          additional_packages,
          additional_post_create_commands
        )

        hetzner_client.post("/servers", config)

        puts "...server #{server_name} created.\n"

        server = find(hetzner_client, server_name)
      end

      server.not_nil!

    rescue ex : Crest::RequestFailed
      STDERR.puts "Failed to create server: #{ex.message}"
      STDERR.puts ex.response

      exit 1
    end
  end

  private def self.find(hetzner_client, server_name)
    servers = ServersList.from_json(hetzner_client.get("/servers")).servers

    servers.find do |server|
      server.name == server_name
    end
  end

  private def self.server_config(
    server_name,
    instance_type,
    image,
    location,
    ssh_key,
    firewall,
    placement_group,
    network,
    additional_packages,
    additional_post_create_commands
  )
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
      user_data: user_data(additional_packages, additional_post_create_commands),
      labels: {
        cluster: server_name,
        role: (server_name =~ /master/ ? "master" : "worker")
      },
      placement_group: placement_group.id
    }
  end

  private def self.user_data(additional_packages = [] of String, additional_post_create_commands = [] of String)
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
