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
    response = Crest.get(
      "#{api_url}#{path}",
      params: params,
      json: true,
      headers: headers
    )

    response.body
  end

  def post(path, params = {} of KeyType => ValueType)
    response = Crest.post(
      "#{api_url}#{path}",
      params.to_json,
      json: true,
      headers: headers,
      handle_errors: false
    )

    success = response.status_code >= 200 && response.status_code < 300

    [success, response.body]
  end

  def put(path, params = {} of KeyType => ValueType)
    response = Crest.put(
      "#{api_url}#{path}",
      params.to_json,
      json: true,
      headers: headers
    )

    response.body
  end

  def delete(path, id)
    response = Crest.delete(
      "#{api_url}#{path}/#{id}",
      json: true,
      headers: headers
    )

    response.body
  end

  private def headers
    {
      "Authorization" => "Bearer #{token}",
    }
  end
end
