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
    packages = %w[fail2ban wireguard]
    packages += additional_packages
    packages = "'#{packages.join("', '")}'"

    mandatory_post_create_commands = [
      "sed -i 's/[#]*PermitRootLogin yes/PermitRootLogin prohibit-password/g' /etc/ssh/sshd_config",
      "sed -i 's/[#]*PasswordAuthentication yes/PasswordAuthentication no/g' /etc/ssh/sshd_config",
      "systemctl restart sshd"
    ]

    post_create_commands = additional_post_create_commands
    post_create_commands += mandatory_post_create_commands
    post_create_commands += final_commands
    post_create_commands = "- #{post_create_commands.join("\n- ")}"

    <<-YAML
    #cloud-config
    packages: [#{packages}]
    runcmd:
    #{post_create_commands}
    YAML
  end
end
