require "../configuration/loader"
require "../hetzner/instance"
require "../util/ssh"
require "./node_detection"

class Cluster::Run
  include Util
  include Util::Shell
  include Kubernetes::Util
  include NodeDetection

  private getter configuration : Configuration::Loader
  private getter hetzner_client : Hetzner::Client do
    configuration.hetzner_client
  end
  private getter settings : Configuration::Main do
    configuration.settings
  end

  def initialize(@configuration)
  end

  def run_command(command : String)
    execute_on_instances("Command to execute: #{command}", "execute this command on all nodes", "Command execution cancelled.", "Command") do |ssh, instance|
      ssh.run(instance, settings.networking.ssh.port.to_s, command, settings.networking.ssh.use_agent, true, disable_log_prefix: true)
      "\nCommand completed successfully"
    end
  end

  def run_script(script_path : String)
    validate_script_file(script_path)

    script_content = File.read(script_path)
    script_name = File.basename(script_path)
    remote_script_path = "/tmp/#{script_name}"

    execute_on_instances("Script to upload and execute: #{script_path}", "upload and execute this script on all nodes", "Script execution cancelled.", "Script") do |ssh, instance|
      # Uploading script...
      upload_command = "cat > #{remote_script_path} << 'EOF'\n#{script_content}\nEOF"
      ssh.run(instance, settings.networking.ssh.port.to_s, upload_command, settings.networking.ssh.use_agent, true, disable_log_prefix: true)

      # Making script executable...
      ssh.run(instance, settings.networking.ssh.port.to_s, "chmod +x #{remote_script_path}", settings.networking.ssh.use_agent, true, disable_log_prefix: true)

      # Executing script...
      execute_command = "#{remote_script_path}"
      ssh.run(instance, settings.networking.ssh.port.to_s, execute_command, settings.networking.ssh.use_agent, true, disable_log_prefix: true)

      # Cleaning up...
      ssh.run(instance, settings.networking.ssh.port.to_s, "rm #{remote_script_path}", settings.networking.ssh.use_agent, false, disable_log_prefix: true)

      "\nScript execution completed successfully"
    end
  end

  private def validate_script_file(script_path : String)
    unless File.exists?(script_path)
      puts "Error: Script file '#{script_path}' does not exist".colorize(:red)
      exit 1
    end

    unless File.file?(script_path)
      puts "Error: '#{script_path}' is not a file".colorize(:red)
      exit 1
    end

    unless File.readable?(script_path)
      puts "Error: Script file '#{script_path}' is not readable".colorize(:red)
      exit 1
    end
  end

  private def execute_on_instances(action_description : String, confirmation_prompt : String, cancellation_message : String, action_type : String, &block : Util::SSH, Hetzner::Instance -> String)
    instances = detect_instances

    print_execution_summary(instances, action_description)
    request_user_confirmation(confirmation_prompt, cancellation_message)

    ssh = setup_ssh_connection
    execute_on_each_instance(ssh, instances, action_type, &block)
  end

  private def print_execution_summary(instances, action_description : String)
    puts "Found #{instances.size} instances in the cluster"
    puts action_description
    puts

    puts "Nodes that will be affected:"
    instances.each do |instance|
      if instance.host_ip_address
        puts "  - #{instance.name} (#{instance.host_ip_address})"
      else
        puts "  - #{instance.name} (no IP address - will be skipped)"
      end
    end
    puts
  end

  private def request_user_confirmation(confirmation_prompt : String, cancellation_message : String)
    print "Type 'continue' to #{confirmation_prompt}: "
    input = gets.try(&.strip)

    if input != "continue"
      puts "#{cancellation_message}".colorize(:yellow)
      exit 0
    end

    puts
  end

  private def setup_ssh_connection
    Util::SSH.new(
      settings.networking.ssh.private_key_path,
      settings.networking.ssh.public_key_path
    )
  end

  private def execute_on_each_instance(ssh : Util::SSH, instances, action_type : String, &block : Util::SSH, Hetzner::Instance -> String)
    instances.each do |instance|
      execute_on_single_instance(ssh, instance, action_type, &block)
    end
  end

  private def execute_on_single_instance(ssh : Util::SSH, instance, action_type : String, &block : Util::SSH, Hetzner::Instance -> String)
    if instance.host_ip_address
      puts "=== Instance: #{instance.name} (#{instance.host_ip_address}) ==="

      begin
        success_message = block.call(ssh, instance)
        puts success_message
      rescue ex : IO::Error
        puts "SSH #{action_type.downcase} failed: #{ex.message}".colorize(:red)
      rescue ex
        puts "Unexpected error: #{ex.message}".colorize(:red)
      end

      puts
    else
      print_skipped_instance(instance)
    end
  end

  private def print_skipped_instance(instance)
    puts "=== Instance: #{instance.name} ==="
    puts "Instance has no IP address, skipping..."
    puts
  end

  private def detect_instances
    detect_instances_with_ips
  end

  private def default_log_prefix
    "Cluster run"
  end
end
