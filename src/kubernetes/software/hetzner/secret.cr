require "../../../util"
require "base64"
require "../../util"
require "./token_reload"

class Kubernetes::Software::Hetzner::Secret
  include Util
  include Kubernetes::Util

  HETZNER_CLOUD_SECRET_MANIFEST = {{ read_file("#{__DIR__}/../../../../templates/hetzner_cloud_secret_manifest.yaml") }}

  private getter configuration : Configuration::Loader
  private getter settings : Configuration::Main { configuration.settings }

  def initialize(@configuration : Configuration::Loader, @settings : Configuration::Main)
  end

  def create : Nil
    log_line "Creating secret for Hetzner Cloud token...", log_prefix: default_log_prefix

    previous_token = current_token_b64
    secret_manifest = build_secret_manifest
    apply_manifest_from_yaml(secret_manifest, "Failed to create Hetzner Cloud secret")

    log_line "...secret created", log_prefix: default_log_prefix

    reload_components_if_token_changed(previous_token)
  end

  # The running pods keep the token they started with, so a rotation only takes effect after a
  # restart. Nothing restarts unless the stored value actually differs.
  private def reload_components_if_token_changed(previous_token : String?) : Nil
    return if previous_token == Base64.strict_encode(settings.hetzner_token)

    token_reload.reload
  end

  private def token_reload : Kubernetes::Software::Hetzner::TokenReload
    Kubernetes::Software::Hetzner::TokenReload.new(@configuration, settings)
  end

  private def current_token_b64 : String?
    result = run_shell_command(
      "kubectl -n kube-system get secret hcloud -o jsonpath='{.data.token}'",
      configuration.kubeconfig_path,
      settings.hetzner_token,
      abort_on_error: false,
      print_output: false
    )

    return nil unless result.success?

    result.output.strip.presence
  end

  private def build_secret_manifest : String
    robot_credentials = settings.robot_credentials
    network = network_name_for_secret
    token = settings.hetzner_token
    robot_user = robot_credentials.try(&.[:user]) || ""
    robot_password = robot_credentials.try(&.[:password]) || ""

    Crinja.render(HETZNER_CLOUD_SECRET_MANIFEST, {
      robot_credentials_enabled: !robot_credentials.nil?,
      network_b64:               Base64.strict_encode(network),
      token_b64:                 Base64.strict_encode(token),
      robot_user_b64:            Base64.strict_encode(robot_user),
      robot_password_b64:        Base64.strict_encode(robot_password),
    })
  end

  private def network_name_for_secret : String
    return "" unless settings.networking.private_network.enabled
    resolve_network_name
  end

  private def default_log_prefix : String
    "Hetzner Cloud Secret"
  end
end
