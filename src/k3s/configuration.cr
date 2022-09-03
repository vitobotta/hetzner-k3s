require "totem"
require "ssh2"

require "../hetzner/client"

module Hetzner::K3s
  class Configuration
    getter configuration_file_path = ""
    getter settings =  Totem::Config.new
    getter errors = [] of String
    getter valid_token : Bool = false
    getter hetzner_token : String | Nil = ""
    getter command : Symbol = :create

    def initialize(configuration_file_path : String, command : Symbol)
      @configuration_file_path = configuration_file_path
      @command = command

      load_yaml

      validate
    end

    private def validate
      # validate_hetzner_token
      validate_cluster_name
      validate_kubeconfig_path_must_exist

      case command
      when :create
        validate_create
      when :delete

      when :upgrade

      end

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

    private def hetzner_client
      @hetzner_client ||= Hetzner::Client.new(hetzner_token)
    end

    private def validate_hetzner_token
      hetzner_token = get("hetzner_token")

      if hetzner_token.nil?
        errors << "Hetzner token is required"
        return
      end

      @hetzner_token = hetzner_token.as_s

      hetzner_client.get("/locations")["locations"]

    rescue ex : Crest::RequestFailed
      errors << "Hetzner token is not valid, unable to consume to Hetzner API"
      return
    end

    private def get(key : String) : Totem::Any | Nil
      settings.get(key)
    rescue Totem::Exception::NotFoundConfigKeyError
      nil
    end

    private def validate_cluster_name
      cluster_name = get("cluster_name")

      if cluster_name.nil?
        errors << "Cluster name is required"
      elsif ! /\A[a-z\d-]+\z/.match cluster_name.as_s
        errors << "Cluster name is an invalid format (only lowercase letters, digits and dashes are allowed)"
      elsif ! /\A[a-z]+.*([a-z]|\d)+\z/.match cluster_name.as_s
        errors << "Ensure that the cluster name starts and ends with a normal letter"
      end
    end

    private def validate_file_path(key : String, description : String)
      path = get(key)

      if path.nil?
        errors << "#{description} is required"
      else
        path = path.as_s

        path = Path[path].expand(home: true).to_s

        if ! File.exists?(path)
          errors << "#{description} does not exist"
        elsif ! File.file?(path)
          errors << "#{description} is not a file"
        end
      end
    end

    private def validate_kubeconfig_path_must_exist
      validate_file_path("kubeconfig_path", "Kubeconfig path")
    end

    private def validate_create
      validate_public_ssh_key
      validate_private_ssh_key
    end

    def validate_public_ssh_key
      validate_file_path("public_ssh_key_path", "Public SSH key")
    end

    def validate_private_ssh_key
      validate_file_path("private_ssh_key_path", "Private SSH key")
    end
  end
end
