require "../../configuration/loader"
require "../../configuration/main"
require "../../util"
require "../util"

# k3s ships local-path as a default StorageClass and re-applies its packaged manifest on every
# start, which puts the is-default-class annotation back. With
# addons.local_path_storage_class.default set to false the class is kept but the annotation is
# overwritten right after k3s' apply, so a different class can stay the only default. The patch
# runs on every `create` for exactly that reason: the installer re-runs after each k3s restart.
class LocalPathStorageClassError < Exception
end

class Kubernetes::Software::LocalPathStorageClass
  include Util
  include Kubernetes::Util

  NAME                  = "local-path"
  DEFAULT_ANNOTATION    = "storageclass.kubernetes.io/is-default-class"
  WAIT_TIMEOUT_SECONDS  = 60
  POLL_INTERVAL_SECONDS =  2
  VERIFY_ATTEMPTS       =  2

  getter wait_timeout_seconds : Int32 = WAIT_TIMEOUT_SECONDS
  getter poll_interval_seconds : Int32 = POLL_INTERVAL_SECONDS

  private getter configuration : Configuration::Loader
  private getter settings : Configuration::Main { configuration.settings }

  def initialize(@configuration : Configuration::Loader, @settings : Configuration::Main)
  end

  def configure : Nil
    addon = settings.addons.local_path_storage_class
    return unless addon.enabled?

    log_line "Configuring the #{NAME} storage class", log_prefix: default_log_prefix

    unless wait_for_storage_class?
      log_line "The #{NAME} storage class did not appear within #{wait_timeout_seconds}s, leaving it as k3s installed it", log_prefix: default_log_prefix
      return
    end

    desired = addon.default?.to_s
    return if current_default_value == desired

    VERIFY_ATTEMPTS.times do |attempt|
      patch_default_value(desired)
      sleep(poll_interval_seconds.seconds)

      return log_default_mode(desired) if current_default_value == desired

      log_line "The #{NAME} default flag was overwritten after the patch, retrying (#{attempt + 1}/#{VERIFY_ATTEMPTS})", log_prefix: default_log_prefix
    end

    raise LocalPathStorageClassError.new("Could not set #{DEFAULT_ANNOTATION} to #{desired} on the #{NAME} storage class")
  end

  private def log_default_mode(desired : String) : Nil
    mode = desired == "true" ? "default" : "non-default, leaving existing default classes alone"
    log_line "The #{NAME} storage class is #{mode}", log_prefix: default_log_prefix
  end

  # A missing class means k3s has not applied its manifest yet.
  private def wait_for_storage_class? : Bool
    deadline = Time.monotonic + wait_timeout_seconds.seconds

    loop do
      return true if storage_class_exists?
      return false if Time.monotonic >= deadline

      sleep(poll_interval_seconds.seconds)
    end
  end

  private def storage_class_exists? : Bool
    run_shell_command(
      "kubectl get storageclass #{NAME} -o name",
      configuration.kubeconfig_path,
      settings.hetzner_token,
      abort_on_error: false,
      print_output: false
    ).success?
  end

  private def current_default_value : String?
    result = run_shell_command(
      "kubectl get storageclass #{NAME} -o jsonpath='{.#{DEFAULT_ANNOTATION.gsub(".", "\\.")}}'",
      configuration.kubeconfig_path,
      settings.hetzner_token,
      abort_on_error: false,
      print_output: false
    )

    return nil unless result.success?

    result.output.strip.presence
  end

  private def patch_default_value(value : String) : Nil
    execute_kubectl_command(
      "kubectl annotate storageclass #{NAME} #{DEFAULT_ANNOTATION}=#{value} --overwrite",
      "Failed to set #{DEFAULT_ANNOTATION}=#{value} on the #{NAME} storage class"
    )
  end

  private def default_log_prefix : String
    "local-path"
  end
end
