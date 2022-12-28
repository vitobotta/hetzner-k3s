require "../client"
require "../server"
require "../servers_list"
require "./find"

class Hetzner::Server::Delete
  getter hetzner_client : Hetzner::Client
  getter server_name : String
  getter server_finder : Hetzner::Server::Find

  def initialize(@hetzner_client, @server_name)
    @server_finder = Hetzner::Server::Find.new(@hetzner_client, @server_name)
  end

  def run
    puts

    begin
      if server = server_finder.run
        puts "Deleting server #{server_name}..."

        hetzner_client.delete("/servers", server.id)

        puts "...server #{server_name} deleted.\n"
      else
        puts "Server #{server_name} does not exist, skipping.\n"
      end

      server_name

    rescue ex : Crest::RequestFailed
      STDERR.puts "Failed to delete server: #{ex.message}"
      STDERR.puts ex.response

      exit 1
    end
  end
end
