require "../client"
require "../server"
require "../servers_list"

class Hetzner::Server::Find
  getter hetzner_client : Hetzner::Client
  getter server_name : String

  def initialize(@hetzner_client, @server_name)
  end

  def run
    servers = ServersList.from_json(hetzner_client.get("/servers",{:name => server_name})).servers
    servers.find do |server|
      server.name == server_name
    end
  rescue ex : Crest::RequestFailed
    STDERR.puts "Failed to fetch servers: #{ex.message}"
    STDERR.puts ex.response
    exit 1
  end
end
