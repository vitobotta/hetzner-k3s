require "crest"
require "yaml"
require "json"

require "./location"
require "./locations_list"
require "./instance_type"
require "./instance_types_list"

class Hetzner::Client
  getter token : String?

  private getter api_url : String = "https://api.hetzner.cloud/v1"

  def initialize(token)
    @token = token
  end

  def locations : Array(Location)
    @locations ||= Hetzner::LocationsList.from_json(get("/locations")).locations
  rescue ex : Crest::RequestFailed
    @locations = [] of Location
  end

  def instance_types : Array(InstanceType)
    @instance_types ||= Hetzner::InstanceTypesList.from_json(get("/server_types")).server_types
  rescue ex : Crest::RequestFailed
    @instance_types = [] of InstanceType
  end

  def get(path, params : Hash = {} of Symbol => String | Bool | Nil) : String
    response = with_rate_limit do
      Crest.get(
        "#{api_url}#{path}",
        params: params,
        json: true,
        headers: headers,
        handle_errors: false
      )
    end

    handle_response(response)
  end

  def post(path, params = {} of KeyType => ValueType)
    response = with_rate_limit do
      Crest.post(
        "#{api_url}#{path}",
        params.to_json,
        json: true,
        headers: headers,
        handle_errors: false
      )
    end

    handle_response(response)
  end

  def put(path, params = {} of KeyType => ValueType)
    response = with_rate_limit do
      Crest.put(
        "#{api_url}#{path}",
        params.to_json,
        json: true,
        headers: headers,
        handle_errors: false
      )
    end

    handle_response(response)
  end

  def delete(path, id)
    response = with_rate_limit do
      Crest.delete(
        "#{api_url}#{path}/#{id}",
        json: true,
        headers: headers,
        handle_errors: false
      )
    end

    handle_response(response)
  end

  private def headers
    {
      "Authorization" => "Bearer #{token}",
    }
  end

  private def handle_rate_limit(response)
    reset_timestamp = response.headers["ratelimit-reset"]

    return unless reset_timestamp.is_a?(String)

    reset_time = reset_timestamp.to_i
    wait_time = reset_time - Time.utc.to_unix + 30

    while wait_time > 0
      reset_time = Time.utc.to_unix + wait_time
      puts "Hetzner API Rate Limit hit. Waiting until #{Time.unix(reset_time).to_s} for reset..."
      sleep_time = [wait_time, 5].min
      sleep(sleep_time)
      wait_time -= sleep_time
    end
  end

  private def with_rate_limit
    while true
      response = yield

      if response.status_code == 429
        handle_rate_limit(response)
      else
        return response
      end
    end
  end

  private def handle_response(response)
    success = response.status_code >= 200 && response.status_code < 300

    [success, response.body]
  end
end
