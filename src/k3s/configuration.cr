require "totem"
require "crest"

require "../hetzner/client"
require "../k3s"
require "../network"

class Hetzner::K3s::Configuration
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
    validate_file_path(configuration_file_path, "Configuration file path is not valid")

    unless errors.empty?
      puts "Some information in the configuration file requires your attention:"

      errors.each do |error|
        STDERR.puts "  - #{error}"
      end

      exit 1
    end

    validate_hetzner_token
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

  private def validate_file_path(path : String, description : String)
    if path.nil?
      errors << "#{description} is required"
    else
      path = Path[path].expand(home: true).to_s

      if ! File.exists?(path)
        errors << "#{description} does not exist"
      elsif ! File.file?(path)
        errors << "#{description} is not a file"
      end
    end
  end

  private def validate_kubeconfig_path_must_exist
    path = get("kubeconfig_path")

    if path.nil?
      errors << "Kubeconfig path is required"
    else
      validate_file_path(path.as_s, "Kubeconfig path")
    end
  end

  private def validate_create
    validate_k3s_version
    validate_public_ssh_key
    validate_private_ssh_key
    validate_ssh_allowed_networks
    validate_api_allowed_networks
  end

  private def validate_public_ssh_key
    path = get("public_ssh_key_path")

    if path.nil?
      errors << "public_ssh_key_path is required"
    else
      validate_file_path(path.as_s, "Public SSH key")
    end
  end

  private def validate_private_ssh_key
    path = get("private_ssh_key_path")

    if path.nil?
      errors << "private_ssh_key_path path is required"
    else
      validate_file_path(path.as_s, "Private SSH key")
    end
  end

  private def validate_networks(network_type : String)
    networks = get("#{network_type.downcase}_allowed_networks")

    if networks.nil?
      errors << "#{network_type} allowed networks are required"
    else
      networks = networks.as_a

      if networks.empty?
        errors << "#{network_type} allowed networks are required"
      else
        networks.each do |network|
          network_cidr = ""

          begin
            network_cidr = network.as_s
          rescue
            errors << "#{network_type} allowed network #{network_cidr} is not a valid network in CIDR notation"
            next
          end

          @errors = errors + Network.new(network_cidr, network_type).validate
        end
      end
    end
  end

  private def validate_ssh_allowed_networks
    validate_networks("SSH")
  end

  private def validate_api_allowed_networks
    validate_networks("API")
  end

  private def validate_k3s_version
    k3s_version = get("k3s_version")

    if k3s_version.nil?
      errors << "K3s version is required"
    elsif ! ::K3s.available_releases.includes?(k3s_version.as_s)
      errors << "K3s version is not valid, run `hetzner-k3s releases` to see available versions"
    end
  end
end
