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
      # validate_hetzner_token
      validate_cluster_name
      validate_kubeconfig_path_must_exist

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

    private def validate_kubeconfig_path_must_exist
      kubeconfig_path = get("kubeconfig_path")

      if kubeconfig_path.nil?
        errors << "Kubeconfig path is required"
      elsif ! File.exists?(kubeconfig_path.as_s)
        errors << "Kubeconfig path does not exist"
      elsif File.directory?(kubeconfig_path.as_s)
        errors << "Kubeconfig path is not a file"
      end
    end
  end
end
