require "base64"
require "crest"
require "json"
require "retriable"

class Hetzner::Robot::Client
  class Error < Exception
  end

  class Server
    getter number : Int32
    getter name : String
    getter ip : String

    def initialize(@number, @name, @ip)
    end
  end

  private getter api_url : String = "https://robot-ws.your-server.de"
  private getter username : String
  private getter password : String
  private getter connect_timeout : Time::Span = 10.seconds
  private getter read_timeout : Time::Span = 30.seconds
  private getter write_timeout : Time::Span = 30.seconds

  def initialize(@username : String, @password : String)
  end

  def server(server_number : Int32) : Server
    success, response = get("/server/#{server_number}")
    raise Error.new("Failed to fetch Robot server #{server_number}: #{response.strip}") unless success

    parse_server(response)
  end

  def update_server_name(server_number : Int32, server_name : String) : Server
    success, response = post("/server/#{server_number}", {"server_name" => server_name})
    raise Error.new("Failed to update Robot server #{server_number} name: #{response.strip}") unless success

    parse_server(response)
  end

  private def get(path)
    response = with_network_retry do
      Crest.get(
        "#{api_url}#{path}",
        headers: headers,
        handle_errors: false,
        connect_timeout: connect_timeout,
        read_timeout: read_timeout,
        write_timeout: write_timeout
      )
    end

    handle_response(response)
  end

  private def post(path, params)
    response = with_network_retry do
      Crest.post(
        "#{api_url}#{path}",
        params,
        headers: headers,
        handle_errors: false,
        connect_timeout: connect_timeout,
        read_timeout: read_timeout,
        write_timeout: write_timeout
      )
    end

    handle_response(response)
  end

  private def headers
    {
      "Authorization" => "Basic #{Base64.strict_encode("#{username}:#{password}")}",
    }
  end

  private def with_network_retry
    Retriable.retry(
      max_attempts: 3,
      backoff: false,
      base_interval: 2.seconds,
      on: {IO::Error, Socket::Error, IO::TimeoutError}
    ) do
      yield
    end
  end

  private def handle_response(response) : Tuple(Bool, String)
    {response.success?, response.body.to_s}
  end

  private def parse_server(response : String) : Server
    server = JSON.parse(response)["server"]
    Server.new(
      server["server_number"].as_i,
      server["server_name"].as_s,
      server["server_ip"].as_s
    )
  rescue ex
    raise Error.new("Robot server response could not be parsed: #{ex.message}")
  end
end
