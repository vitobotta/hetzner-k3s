# frozen_string_literal: true

module Hetzner
  class Client
    BASE_URI = 'https://api.hetzner.cloud/v1'

    attr_reader :token

    def initialize(token:)
      @token = token
    end

    def get(path)
      make_request do
        JSON.parse HTTParty.get(BASE_URI + path, headers: headers).body
      end
    end

    def post(path, data)
      make_request do
        HTTParty.post(BASE_URI + path, body: data.to_json, headers: headers)
      end
    end

    def delete(path, id)
      make_request do
        HTTParty.delete("#{BASE_URI}#{path}/#{id}", headers: headers)
      end
    end

    private

    def headers
      {
        'Authorization' => "Bearer #{@token}",
        'Content-Type' => 'application/json'
      }
    end

    def make_request(&block)
      retries ||= 0

      Timeout.timeout(30) do
        block.call
      end
    rescue Timeout::Error
      retry if (retries += 1) < 3
    end
  end
end
