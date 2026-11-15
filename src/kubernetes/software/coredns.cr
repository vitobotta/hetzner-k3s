require "../../configuration/loader"
require "../../configuration/main"
require "../../util"
require "../util"

# CoreDNS is a k3s packaged component, so k3s owns it by default and re-applies its manifest on
# every start. With addons.coredns.enabled the tool instead starts k3s with --disable coredns and
# deploys its own copy of the manifest, which allows resources, replicas and image to be set.
#
# Object names and the k8s-app=kube-dns labels are kept identical to the k3s manifest: a
# node-local DNS cache forwards cluster.local to the kube-dns-upstream Service, which selects that
# label, and pod resolv.conf files pin the kube-dns ClusterIP.
#
# Disabling the toggle reverses the change: the k3s defaults are rendered and applied straight
# away, so the reversal does not wait for k3s to restart, then the ownership label is removed and
# k3s owns the object again.
class Kubernetes::Software::CoreDNS
  include Util
  include Kubernetes::Util

  DEPLOYMENT_NAME    = "coredns"
  NAMESPACE          = "kube-system"
  MANAGED_LABEL      = "hetzner-k3s-managed"
  MANAGED_LABEL_LINE = "    #{MANAGED_LABEL}: coredns\n"
  CONTAINER_INDENT   = "          "

  # k3s defaults, used for whatever the config does not override.
  DEFAULT_REPLICAS        = 1
  DEFAULT_LIMITS_MEMORY   = "170Mi"
  DEFAULT_REQUESTS_CPU    = "100m"
  DEFAULT_REQUESTS_MEMORY = "70Mi"

  MANIFEST_TEMPLATE = {{ read_file("#{__DIR__}/../../../templates/coredns.yaml") }}

  # A missing deployment means k3s has not applied its manifest yet. A vanished one means the
  # packaged AddOn pruned our objects, which happens once while the toggle is switched on.
  getter missing_deployment_timeout_seconds : Int32 = 30
  getter verify_timeout_seconds : Int32 = 15
  getter rollout_timeout_seconds : Int32 = 120
  getter poll_interval_seconds : Int32 = 2

  private getter configuration : Configuration::Loader
  private getter settings : Configuration::Main { configuration.settings }

  def initialize(@configuration : Configuration::Loader, @settings : Configuration::Main)
  end

  def install : Nil
    if settings.addons.coredns.enabled?
      adopt
    else
      release
    end
  end

  private def adopt : Nil
    log_line "Deploying a hetzner-k3s managed CoreDNS. k3s's packaged manifest is disabled, so expect a short DNS gap while it is replaced.", log_prefix: default_log_prefix

    manifest = render(managed: true)
    apply(manifest)
    verify(manifest)
  end

  private def release : Nil
    unless managed_by_tool?
      reconcile_replicas
      return
    end

    log_line "addons.coredns is disabled, handing CoreDNS back to k3s", log_prefix: default_log_prefix

    apply(render(managed: false))
    remove_managed_label
    wait_for_rollout
  end

  # The packaged AddOn prunes the resources it owns once k3s starts with --disable coredns. That
  # can land after this apply, so watch the deployment for a while and apply again if it goes away.
  private def verify(manifest : String) : Nil
    deadline = Time.monotonic + verify_timeout_seconds.seconds
    reapplied = false

    while Time.monotonic < deadline
      if !managed_by_tool? && !reapplied
        log_line "CoreDNS was removed by the k3s AddOn prune, applying it again", log_prefix: default_log_prefix
        apply(manifest)
        reapplied = true
      end

      sleep poll_interval_seconds.seconds
    end

    unless managed_by_tool?
      log_line "CoreDNS deployment is still missing after #{verify_timeout_seconds}s, run create again", log_prefix: default_log_prefix
      return
    end

    wait_for_rollout
    log_line "CoreDNS deployed with #{settings.addons.coredns.replicas || DEFAULT_REPLICAS} replica(s)", log_prefix: default_log_prefix
  end

  private def reconcile_replicas : Nil
    desired = settings.addons.coredns.replicas
    return unless desired

    current = wait_for_deployment_replicas

    unless current
      log_line "CoreDNS deployment not found in #{NAMESPACE}, leaving its replica count unchanged", log_prefix: default_log_prefix
      return
    end

    return if current == desired

    log_line "Setting replica count to #{desired} (was #{current})", log_prefix: default_log_prefix
    apply_kubectl_command(scale_command(desired), "Failed to set the CoreDNS replica count")
  end

  private def wait_for_deployment_replicas : Int32?
    deadline = Time.monotonic + missing_deployment_timeout_seconds.seconds

    loop do
      replicas = deployment_replicas
      return replicas if replicas
      return nil if Time.monotonic >= deadline

      sleep poll_interval_seconds.seconds
    end
  end

  private def deployment_replicas : Int32?
    result = run_shell_command(
      "kubectl get deployment #{DEPLOYMENT_NAME} -n #{NAMESPACE} -o jsonpath='{.spec.replicas}'",
      configuration.kubeconfig_path,
      settings.hetzner_token,
      abort_on_error: false,
      print_output: false
    )

    return nil unless result.success?

    result.output.strip.to_i?
  end

  private def managed_by_tool? : Bool
    result = run_shell_command(
      "kubectl get deployment #{DEPLOYMENT_NAME} -n #{NAMESPACE} -o jsonpath='{.metadata.labels.#{MANAGED_LABEL}}'",
      configuration.kubeconfig_path,
      settings.hetzner_token,
      abort_on_error: false,
      print_output: false
    )

    result.success? && result.output.strip == DEPLOYMENT_NAME
  end

  private def apply(manifest : String) : Nil
    apply_manifest_from_yaml(manifest, "Failed to apply the CoreDNS manifest")
  end

  private def remove_managed_label : Nil
    command = "kubectl label deployment #{DEPLOYMENT_NAME} -n #{NAMESPACE} #{MANAGED_LABEL}- --overwrite"
    apply_kubectl_command(command, "Failed to remove the CoreDNS ownership label")
  end

  private def wait_for_rollout : Nil
    command = "kubectl rollout status deployment #{DEPLOYMENT_NAME} -n #{NAMESPACE} --timeout=#{rollout_timeout_seconds}s"
    result = run_shell_command(command, configuration.kubeconfig_path, settings.hetzner_token)

    return if result.success?

    log_line "CoreDNS did not finish rolling out within #{rollout_timeout_seconds}s: #{result.output.strip}", log_prefix: default_log_prefix
  end

  private def scale_command(replicas : Int32) : String
    "kubectl scale deployment #{DEPLOYMENT_NAME} -n #{NAMESPACE} --replicas=#{replicas}"
  end

  def render(managed : Bool) : String
    rendered = MANIFEST_TEMPLATE
      .gsub("__REPLICAS__", (settings.addons.coredns.replicas || DEFAULT_REPLICAS).to_s)
      .gsub("__IMAGE__", settings.addons.coredns.image)
      .gsub("__CLUSTER_DOMAIN__", settings.networking.cluster_domain || "cluster.local")
      .gsub("__CLUSTER_DNS__", settings.networking.cluster_dns)
      .gsub("__RESOURCES__", resources_block)

    managed ? rendered : rendered.gsub(MANAGED_LABEL_LINE, "")
  end

  private def resources_block : String
    lines = [] of String
    lines << "#{CONTAINER_INDENT}limits:"
    lines << "#{CONTAINER_INDENT}  memory: #{memory_limit}"
    lines << "#{CONTAINER_INDENT}requests:"
    lines << "#{CONTAINER_INDENT}  cpu: #{cpu_request}"
    lines << "#{CONTAINER_INDENT}  memory: #{memory_request}"

    "\n#{lines.join("\n")}"
  end

  private def configured_resources
    settings.addons.coredns.resources
  end

  private def memory_limit : String
    configured_resources.limits.memory || DEFAULT_LIMITS_MEMORY
  end

  private def cpu_request : String
    configured_resources.requests.cpu || DEFAULT_REQUESTS_CPU
  end

  private def memory_request : String
    configured_resources.requests.memory || DEFAULT_REQUESTS_MEMORY
  end

  private def default_log_prefix : String
    "CoreDNS"
  end
end
