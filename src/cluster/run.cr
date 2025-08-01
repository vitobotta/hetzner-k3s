require "../configuration/loader"
require "../hetzner/instance"
require "../util/ssh"
require "../util/shell"
require "../kubernetes/util"
require "../util"

class Cluster::Run
  include Util
  include Util::Shell
  include Kubernetes::Util

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
      "Command completed successfully"
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

      "Script execution completed successfully"
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
    instances = detect_instances_with_kubectl
    return instances unless instances.empty?

    detect_instances_with_hetzner_api
  end

  private def detect_instances_with_kubectl
    instances = [] of Hetzner::Instance

    result = run_shell_command("kubectl get nodes --no-headers -o custom-columns=NAME:.metadata.name --request-timeout=10s 2>/dev/null", configuration.kubeconfig_path, settings.hetzner_token, abort_on_error: false, print_output: false)
    return instances unless result.success?

    node_names = result.output.split("\n").reject(&.empty?)

    node_names.each do |node_name|
      addresses_result = run_shell_command("kubectl get node #{node_name} -o json --request-timeout=10s 2>/dev/null", configuration.kubeconfig_path, settings.hetzner_token, abort_on_error: false, print_output: false)

      if addresses_result.success? && !addresses_result.output.blank?
        begin
          node_json = JSON.parse(addresses_result.output)
          addresses = node_json["status"]["addresses"].as_a

          internal_ip = ""
          external_ip = ""

          addresses.each do |address|
            addr_type = address["type"].as_s
            addr_value = address["address"].as_s

            case addr_type
            when "InternalIP"
              internal_ip = addr_value
            when "ExternalIP"
              external_ip = addr_value
            end
          end

          if !internal_ip.blank? || !external_ip.blank?
            instances << Hetzner::Instance.new(0, "running", node_name, internal_ip, external_ip)
          end
        rescue ex
          puts "Warning: Failed to parse node data for #{node_name}: #{ex.message}".colorize(:yellow)
        end
      end
    end

    instances
  end

  private def detect_instances_with_hetzner_api
    instances = [] of Hetzner::Instance

    find_instances_by_label("cluster=#{settings.cluster_name}", instances)

    settings.worker_node_pools.each do |pool|
      next unless pool.autoscaling_enabled

      node_group_name = pool.include_cluster_name_as_prefix ? "#{settings.cluster_name}-#{pool.name}" : pool.name
      find_instances_by_label("hcloud/node-group=#{node_group_name}", instances)
    end

    instances
  end

  private def find_instances_by_label(label_selector, instances)
    success, response = hetzner_client.get("/servers", {:label_selector => label_selector})
    return unless success

    JSON.parse(response)["servers"].as_a.each do |instance_data|
      instance_name = instance_data["name"].as_s
      instance_status = instance_data["status"].as_s
      instance_id = instance_data["id"].as_i

      internal_ip = ""
      external_ip = ""

      if pub_net = instance_data["public_net"]?
        if ipv4 = pub_net["ipv4"]?
          external_ip = ipv4["ip"].as_s
        end
      end

      if private_net = instance_data["private_net"]?
        if private_net.as_a.size > 0
          internal_ip = private_net.as_a[0]["ip"].as_s
        end
      end

      instances << Hetzner::Instance.new(instance_id, instance_status, instance_name, internal_ip, external_ip)
    end
  end

  private def default_log_prefix
    "Cluster run"
  end
end
