require "crest"
require "yaml"
require "json"

require "./location"
require "./locations_list"
require "./server_type"
require "./server_types_list"

class Hetzner::Client
  getter token : String | Nil

  private getter api_url : String = "https://api.hetzner.cloud/v1"
  getter locations : Array(Location) = [] of Location

  def initialize(token : String | Nil)
    @token = token
  end

  def valid_token?
    return @valid_token unless @valid_token.nil?

    if token.nil? || token.try &.empty?
      @valid_token = false
      return false
    end

    @locations = Hetzner::LocationsList.from_json(get("/locations")).locations

    @valid_token = true
  rescue ex : Crest::RequestFailed
    @valid_token = false
  end

  def server_types : Array(ServerType)
    return [] of ServerType unless valid_token?

    @server_types ||= Hetzner::ServerTypesList.from_json(get("/server_types")).server_types
  rescue ex : Crest::RequestFailed
    @server_types = [] of ServerType
  end

  def get(path, params : Hash = {} of Symbol => String | Bool | Nil) : String
    response = Crest.get(
      "#{api_url}#{path}",
      params,
      json: true,
      headers: headers
    )

    response.body
  end

  def post(path, params)
    response = Crest.post(
      "#{api_url}#{path}",
      params,
      json: true,
      headers: headers
    )

    response.body
  end

  def put(path, params = {} of KeyType => ValueType)
    response = Crest.put(
      "#{api_url}#{path}",
      params,
      json: true,
      headers: headers
    )

    response.body
  end

  def delete(path, params = {} of KeyType => ValueType)
    response = Crest.delete(
      "#{api_url}#{path}",
      params,
      json: true,
      headers: headers
    )

    response.body
  end

  private def headers
    {
      "Authorization" => "Bearer #{token}",
      "Content-Type" => "application/json",
      "Accept" => "application/json"
    }
  end
end
