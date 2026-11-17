require "../../../configuration/loader"
require "../../../configuration/main"
require "../../../util"
require "../../util"

# The Hetzner components read the API token from the hcloud secret once, when their pods start. After
# a token rotation the running pods keep the old token, the Cloud Controller Manager then fails to
# authenticate and new nodes stay tainted node.cloudprovider.kubernetes.io/uninitialized.
#
# Rolling the pods is the only way to pick the new token up, so a changed token rolls every component
# that consumes it. Nothing rolls while the token is unchanged, which keeps ordinary runs quiet.
class Kubernetes::Software::Hetzner::TokenReload
  include Util
  include Kubernetes::Util

  NAMESPACE       = "kube-system"
  ROLLOUT_TIMEOUT = "180s"
  POLL_INTERVAL   = 2
  STATUS_ATTEMPTS = 3

  # kind, name, addon the component belongs to
  COMPONENTS = [
    {"deployment", "hcloud-cloud-controller-manager", :cloud_controller_manager},
    {"deployment", "hcloud-csi-controller", :csi_driver},
    {"daemonset", "hcloud-csi-node", :csi_driver},
    {"deployment", "cluster-autoscaler", :cluster_autoscaler},
  ]

  getter rollout_timeout : String = ROLLOUT_TIMEOUT
  getter poll_interval : Time::Span = POLL_INTERVAL.seconds

  private getter configuration : Configuration::Loader
  private getter settings : Configuration::Main { configuration.settings }

  def initialize(@configuration : Configuration::Loader, @settings : Configuration::Main)
  end

  def reload : Nil
    log_line "The Hetzner API token changed, restarting the Hetzner components so they pick it up", log_prefix: default_log_prefix

    restarted = COMPONENTS.select { |component| addon_enabled?(component[2]) && exists?(component[0], component[1]) }
    return log_nothing_to_restart if restarted.empty?

    restarted.each do |component|
      execute_kubectl_command(
        "kubectl -n #{NAMESPACE} rollout restart #{component[0]}/#{component[1]}",
        "Failed to restart #{component[1]}"
      )
    end

    restarted.each { |component| wait_for_rollout(component[0], component[1]) }
  end

  private def log_nothing_to_restart : Nil
    log_line "No running Hetzner component needs a restart", log_prefix: default_log_prefix
  end

  private def addon_enabled?(addon : Symbol) : Bool
    case addon
    when :cloud_controller_manager
      settings.addons.cloud_controller_manager.enabled?
    when :csi_driver
      settings.addons.csi_driver.enabled?
    when :cluster_autoscaler
      settings.addons.cluster_autoscaler.enabled?
    else
      false
    end
  end

  private def exists?(kind : String, name : String) : Bool
    run_shell_command(
      "kubectl -n #{NAMESPACE} get #{kind} #{name} -o name",
      configuration.kubeconfig_path,
      settings.hetzner_token,
      abort_on_error: false,
      print_output: false
    ).success?
  end

  # A stalled rollout is logged rather than failing the whole run: the cluster itself is fine either
  # way and the operator can look at it afterwards.
  private def wait_for_rollout(kind : String, name : String) : Nil
    STATUS_ATTEMPTS.times do |attempt|
      result = run_shell_command(
        "kubectl -n #{NAMESPACE} rollout status #{kind}/#{name} --timeout=#{rollout_timeout}",
        configuration.kubeconfig_path,
        settings.hetzner_token,
        abort_on_error: false,
        print_output: false
      )

      return if result.success?

      log_line "#{name} did not finish rolling out (#{attempt + 1}/#{STATUS_ATTEMPTS}): #{result.output.strip}", log_prefix: default_log_prefix
      sleep(poll_interval)
    end
  end

  private def default_log_prefix : String
    "Hetzner components"
  end
end
