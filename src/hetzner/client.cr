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
  private getter mutex : Mutex = Mutex.new

  def initialize(token)
    @token = token
  end

  def locations : Array(Location)
    @locations ||= begin
      success, response = get("/locations")

      if success
        Hetzner::LocationsList.from_json(response).locations
      else
        puts "[Preflight checks] Unable to fetch locations via Hetzner API"
        exit 1
      end
    end
  end

  def instance_types : Array(InstanceType)
    @instance_types ||= begin
      success, response = get("/server_types")

      if success
        Hetzner::InstanceTypesList.from_json(response).server_types
      else
        puts "[Preflight checks] Unable to fetch instance types via Hetzner API"
        exit 1
      end
    end
  end

  def get(path, params : Hash = {} of Symbol => String | Bool | Nil)
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
        params,
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
        params,
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
    @headers ||= {
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
      remaining_time = Time::Span.new(seconds: wait_time)
      puts "[Hetzner API] Rate Limit hit. Waiting for #{remaining_time.total_hours.floor}h#{remaining_time.minutes.floor}m#{remaining_time.seconds.floor}s until reset..."
      sleep_time = [wait_time, 5].min
      sleep(sleep_time.seconds)
      wait_time -= sleep_time
    end
  end

  private def with_rate_limit
    while true
      response = yield

      if response.status_code == 429
        mutex.synchronize do
          handle_rate_limit(response)
        end
      else
        return response
      end
    end
  end

  private def handle_response(response) : Tuple(Bool, String)
    success = response.status_code >= 200 && response.status_code < 300

    {success, response.body.to_s}
  end
end
