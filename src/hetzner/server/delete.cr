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
        puts "Deleting server #{server_name}...".colorize(:light_gray)

        hetzner_client.delete("/servers", server.id)

        puts "...server #{server_name} deleted.\n".colorize(:light_gray)
      else
        puts "Server #{server_name} does not exist, skipping.\n".colorize(:light_gray)
      end

    rescue ex : Crest::RequestFailed
      STDERR.puts "Failed to delete server: #{ex.message}".colorize(:red)
      STDERR.puts ex.response

      exit 1
    end
  end
end
