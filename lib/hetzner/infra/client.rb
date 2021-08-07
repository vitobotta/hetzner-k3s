module Hetzner
  class Client
    BASE_URI = "https://api.hetzner.cloud/v1"

    attr_reader :token

    def initialize(token:)
      @token = token
    end

    def get(path)
      JSON.parse HTTP.headers(headers).get(BASE_URI + path).body
    end

    def post(path, data)
      HTTP.headers(headers).post(BASE_URI + path, json: data)
    end

    def delete(path, id)
      HTTP.headers(headers).delete(BASE_URI + path + "/" + id.to_s)
    end

    private

      def headers
        {
          "Authorization": "Bearer #{@token}",
          "Content-Type": "application/json"
        }
      end
  end
end
