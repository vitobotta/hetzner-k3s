require "crest"
require "yaml"
require "json"

class Hetzner::Client
  getter token : String | Nil

  private getter api_url : String = "https://api.hetzner.cloud/v1"
  getter locations : Array(String) = [] of String

  def initialize(token : String | Nil)
    @token = token
  end

  def valid_token?
    return @valid_token unless @valid_token.nil?

    if token.nil? || token.try &.empty?
      @valid_token = false
      return false
    end

    @locations = get("/locations")["locations"].as_a.map do |location|
      location["name"].as_s
    end

    @valid_token = true
  rescue ex : Crest::RequestFailed
    @valid_token = false
  end

  def server_types : Array(String)
    return [] of String unless valid_token?

    @server_types ||= get("/server_types")["server_types"].as_a.map do |server_type|
      server_type["name"].as_s
    end
  rescue ex : Crest::RequestFailed
    @server_types = [] of String
  end

  def get(path, params = {} of String => String | Bool | Nil) : JSON::Any
    response = Crest.get(
      "#{api_url}#{path}",
      params: params,
      json: true,
      headers: headers
    )

    JSON.parse response.body
  end

  def post(path, params = {} of KeyType => ValueType)
    response = Crest.post(
      "#{api_url}#{path}",
      params: params,
      json: true,
      headers: headers
    )

    JSON.parse response.body
  end

  def put(path, params = {} of KeyType => ValueType)
    response = Crest.put(
      "#{api_url}#{path}",
      params: params,
      json: true,
      headers: headers
    )

    JSON.parse response.body
  end

  def delete(path, params = {} of KeyType => ValueType)
    response = Crest.delete(
      "#{api_url}#{path}",
      params: params,
      json: true,
      headers: headers
    )

    JSON.parse response.body
  end

  private def headers
    {
      "Authorization" => "Bearer #{token}",
      "Content-Type" => "application/json",
      "Accept" => "application/json"
    }
  end
end
