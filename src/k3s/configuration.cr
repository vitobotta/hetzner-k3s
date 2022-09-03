require "totem"

module Hetzner::K3s
  class Configuration
    property configuration_file_path = ""
    property settings =  Totem::Config.new
    property errors = [] of String

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
      token = get("hetzner_token")

      if token.nil?
        errors << "hetzner_token is required"
        return
      end
    end

    private def get(key : String) : Totem::Any?
      settings.get(key)
    rescue Totem::Exception::NotFoundConfigKeyError
      nil
    end
  end
end
