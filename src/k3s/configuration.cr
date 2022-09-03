require "totem"

require "../hetzner/client"

module Hetzner::K3s
  class Configuration
    property configuration_file_path = ""
    property settings =  Totem::Config.new
    property errors = [] of String
    property valid_token : Bool = false
    property hetzner_token : String | Nil = ""

    def initialize(configuration_file_path : String)
      @configuration_file_path = configuration_file_path

      load_yaml

      validate
    end

    private def validate
      validate_hetzner_token

      unless errors.empty?
        puts "Some information in the configuration file requires your attention:"

        errors.each do |error|
          STDERR.puts "  - #{error}"
        end
      end
    end

    private def load_yaml
      @settings = Totem.from_file(configuration_file_path)
    rescue
      STDERR.puts "Could not load configuration file: #{configuration_file_path}"
      exit 1
    end

    private def validate_hetzner_token
      hetzner_token = get("hetzner_token")

      if hetzner_token.nil?
        errors << "hetzner_token is required"
        return
      end

      @hetzner_token = hetzner_token.as_s

      hetzner_client.get("/locations")["locations"]

    rescue ex : Crest::RequestFailed
      errors << "hetzner_token is not valid, unable to consume to Hetzner API"
      return
    end

    private def get(key : String) : Totem::Any | Nil
      settings.get(key)
    rescue Totem::Exception::NotFoundConfigKeyError
      nil
    end


    private def hetzner_client
      @hetzner_client ||= Hetzner::Client.new(hetzner_token)
    end
  end
end
