require "./routing_spec_helper"
require "../src/kubernetes/kubeconfig_manager"

# The flattened kubeconfig has to select the load balancer context once its public interface is
# disabled, because the master contexts then carry an address that is not reachable from the
# private network the API is meant to be used from. Without the setting the first master stays
# the default context, as before the load balancer could be made private.
module KubeconfigContextSpec
  LB_PRIVATE_IP = "10.20.0.254"

  def self.master
    Hetzner::Instance.new(1, "running", "routing-test-master1", "10.20.0.5", "192.0.2.5")
  end

  def self.load_balancer
    Hetzner::LoadBalancer.from_json(%({"id": 1, "name": "routing-test-api", "private_net": [{"ip": "#{LB_PRIVATE_IP}", "network": 1}], "public_net": {"enabled": false, "ipv4": {"ip": "198.51.100.7"}}, "targets": [{"use_private_ip": true}]}))
  end

  def self.yaml(flag : Bool, kubeconfig_path : String) : String
    RoutingSpec.config
      .sub("/nonexistent/kubeconfig", kubeconfig_path)
      .+("create_load_balancer_for_the_kubernetes_api: true\n")
      .+("disable_public_interface_for_the_kubernetes_api_load_balancer: #{flag}\n")
  end

  # What the master answers with for the k3s kubeconfig; the real one is rewritten and flattened.
  class SSHDouble < Util::SSH
    def run(instance, port, command, use_ssh_agent, print_output = true, disable_log_prefix = false, capture_output = false)
      <<-KUBECONFIG
      apiVersion: v1
      kind: Config
      current-context: default
      clusters:
      - name: default
        cluster:
          server: https://127.0.0.1:6443
      KUBECONFIG
    end
  end

  # Records the kubectl calls instead of running them, and writes the file the flatten would create.
  class RecordingManager < Kubernetes::KubeconfigManager
    getter commands = [] of String

    def run_shell_command(command : String, kubeconfig_path : String, hetzner_token : String, error_message : String = "", abort_on_error : Bool = true, log_prefix : String = "", print_output : Bool = true) : Util::Shell::CommandResult
      @commands << command

      if command.includes?("--flatten")
        File.write(command.split(">").last.strip, "apiVersion: v1\ncurrent-context: flattened\n")
      end

      Util::Shell::CommandResult.new("", 0)
    end

    def selected_context : String
      commands.find(&.includes?("use-context")).to_s.split("use-context ").last.strip
    end
  end

  def self.selected_context(flag : Bool) : String
    path = File.tempname("kubeconfig-context-spec", ".yaml")
    recorder : RecordingManager? = nil

    RoutingSpec.with_loader(yaml(flag, path)) do |loader|
      manager = RecordingManager.new(loader, loader.settings, SSHDouble.new("/nonexistent/test-key"))
      manager.save_kubeconfig([master], master, load_balancer)
      recorder = manager
    end

    recorder.not_nil!.selected_context
  ensure
    path.try do |p|
      [p, "#{p}-routing-test"].each { |file| File.delete(file) if File.exists?(file) }
    end
  end
end

describe Kubernetes::KubeconfigManager do
  it "selects the load balancer context when the public interface is disabled" do
    KubeconfigContextSpec.selected_context(true).should eq("routing-test")
  end

  it "selects the first master context without the setting" do
    KubeconfigContextSpec.selected_context(false).should eq("routing-test-master1")
  end
end
