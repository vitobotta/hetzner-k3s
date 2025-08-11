require "../../configuration/loader"
require "../../configuration/main"
require "../../hetzner/instance"
require "../../util/ssh"
require "../../util/shell"
require "../script/master_generator"
require "../kubeconfig_manager"

class Kubernetes::ControlPlane::Setup
  include Util::Shell

  def initialize(
    @configuration : Configuration::Loader,
    @settings : Configuration::Main,
    @ssh : ::Util::SSH,
    @master_generator : Kubernetes::Script::MasterGenerator,
    @kubeconfig_manager : Kubernetes::KubeconfigManager
  )
  end

  def set_up_control_plane(masters_installation_queue_channel, master_count, load_balancer)
    masters = [] of Hetzner::Instance
    master_count.times { masters << masters_installation_queue_channel.receive }

    first_master = identify_first_master(masters)
    set_up_first_master(first_master, masters, load_balancer)

    set_up_additional_masters(masters, first_master, load_balancer)

    {masters, first_master}
  end

  private def set_up_first_master(first_master : Hetzner::Instance, masters : Array(Hetzner::Instance), load_balancer)
    wait_for_cloud_init(first_master)
    install_script = @master_generator.generate_script(first_master, masters, first_master, load_balancer, @kubeconfig_manager)
    output = deploy_to_instance(first_master, install_script)

    log_line "Waiting for the control plane to be ready...", log_prefix: "Instance #{first_master.name}"
    sleep 10.seconds unless /No change detected/ =~ output

    # Save kubeconfig and validate the first master is working properly
    validate_first_master_setup!(masters, first_master, load_balancer)
  end

  private def set_up_additional_masters(masters : Array(Hetzner::Instance), first_master : Hetzner::Instance, load_balancer)
    additional_masters = masters - [first_master]
    return if additional_masters.empty?

    masters_ready_channel = Channel(Hetzner::Instance).new

    additional_masters.each do |master|
      spawn do
        deploy_to_master(master, masters, first_master, load_balancer)
        masters_ready_channel.send(master)
      end
    end

    additional_masters.size.times { masters_ready_channel.receive }
  end

  private def deploy_to_master(instance : Hetzner::Instance, masters : Array(Hetzner::Instance), first_master : Hetzner::Instance, load_balancer)
    wait_for_cloud_init(instance)
    script = @master_generator.generate_script(instance, masters, first_master, load_balancer, @kubeconfig_manager)
    deploy_to_instance(instance, script)
  end

  private def wait_for_cloud_init(instance : Hetzner::Instance)
    cloud_init_wait_script = {{ read_file("#{__DIR__}/../../../templates/cloud_init_wait_script.sh") }}
    @ssh.run(instance, @settings.networking.ssh.port, cloud_init_wait_script, @settings.networking.ssh.use_agent)
  end

  private def deploy_to_instance(instance : Hetzner::Instance, script : String) : String
    @ssh.run(instance, @settings.networking.ssh.port, script, @settings.networking.ssh.use_agent)
  end

  private def identify_first_master(masters : Array(Hetzner::Instance)) : Hetzner::Instance
    token = K3s.k3s_token(@settings, masters)
    return masters[0] if token.empty?

    # Sort masters by token file creation timestamp (oldest first)
    # Masters without a token file will be sorted to the end
    sorted_masters = masters.sort_by do |master|
      timestamp = K3s.get_token_file_timestamp(@settings, master)
      # Use a very future time for masters without timestamp so they sort to the end
      timestamp || Time.utc(9999, 1, 1)
    end

    bootstrapped_master = sorted_masters.find { |master| K3s.get_token_from_master(@settings, master) == token }
    bootstrapped_master || masters[0]
  end

  private def validate_first_master_setup!(masters : Array(Hetzner::Instance), first_master : Hetzner::Instance, load_balancer)
    # Determine master terminology based on cluster size
    master_terminology = masters.size > 1 ? "first master" : "master"
    log_prefix = masters.size > 1 ? "First Master Validation" : "Master Validation"

    begin
      # Save kubeconfig first
      @kubeconfig_manager.save_kubeconfig(masters, first_master, load_balancer)
      sleep 5.seconds

      # Validate the master setup using existing wait_for_control_plane method
      log_line "Validating #{master_terminology} setup...", log_prefix: "Instance #{first_master.name}"

      wait_for_control_plane

      log_line "✅ #{master_terminology.capitalize} validation successful", log_prefix: log_prefix
    rescue ex : Exception | Tasker::Timeout
      error_message = ex.is_a?(Tasker::Timeout) ? "Timeout waiting for control plane to be ready" : ex.message
      log_line "❌ Critical error during #{master_terminology} validation: #{error_message}", log_prefix: log_prefix
      log_line "   This indicates a problem with the configuration affecting the #{master_terminology}.", log_prefix: log_prefix
      if masters.size > 1
        log_line "   Aborting early to avoid affecting remaining masters.", log_prefix: log_prefix
      end
      log_line "   Please check your configuration and try again.", log_prefix: log_prefix
      exit 1
    end
  end

  private def wait_for_control_plane
    command = "kubectl cluster-info 2> /dev/null"
    Retriable.retry(max_attempts: 3, on: Tasker::Timeout, backoff: false) do
      Tasker.timeout(30.seconds) do
        loop do
          result = run_shell_command(command, @configuration.kubeconfig_path, @settings.hetzner_token, log_prefix: "Control plane", abort_on_error: false, print_output: false)
          break if result.output.includes?("running")
          sleep 1.seconds
        end
      end
    end
  end

  private def default_log_prefix
    "Control Plane Setup"
  end

  private def log_line(message, log_prefix = default_log_prefix)
    puts "[#{log_prefix}] #{message}"
  end
end

