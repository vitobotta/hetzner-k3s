require "yaml"

class Configuration::Settings::NewK3sVersion
  getter errors : Array(String)
  getter current_k3s_version : String
  getter new_k3s_version : String?
  getter releases : Array(String) | Array(YAML::Any) { ::K3s.available_releases }
  getter new_version : String { new_k3s_version.not_nil! }

  def initialize(@errors, @current_k3s_version, @new_k3s_version)
  end

  def validate
    validate_release_number
    validate_new_version_must_be_more_recent
  end

  private def validate_release_number
    return if releases.includes?(new_version)

    errors << "New k3s version is not valid, run `hetzner-k3s releases` to see available versions"
  end

  private def validate_new_version_must_be_more_recent
    current_version_index = releases.index(current_k3s_version) || -1
    new_version_index = releases.index(new_version) || -1

    return if new_version_index > current_version_index

    errors << "New k3s version must be more recent than current version"
  end
end
