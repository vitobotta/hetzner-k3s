class Configuration::Settings::K3sVersion
  getter errors : Array(String)
  getter k3s_version : String

  def initialize(@errors, @k3s_version)
  end

  def validate
    return if K3s.available_releases.includes?(@k3s_version)

    errors << "K3s version is not valid, run `hetzner-k3s releases` to see available versions"
  end
end
