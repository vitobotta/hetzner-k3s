require "../main"

class Configuration::Validators::JoinViaApiServerHostname
  getter errors : Array(String) = [] of String
  getter settings : Configuration::Main

  def initialize(@errors, @settings)
  end

  def validate
    return unless settings.join_via_api_server_hostname

    if settings.api_server_hostname.nil?
      errors << "join_via_api_server_hostname requires api_server_hostname to be set"
    end
  end
end
