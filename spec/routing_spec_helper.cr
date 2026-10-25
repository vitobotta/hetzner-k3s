require "spec"
require "file_utils"
require "colorize"
require "../src/configuration/loader"
require "../src/configuration/validators/external_routing"
require "../src/configuration/validators/external_node_pool"
require "../src/k3s"
require "../src/kubernetes/script/master_generator"
require "../src/kubernetes/script/worker_generator"
require "../src/cluster/run"
require "../src/kubernetes/local_firewall/setup"

module RoutingSpec
  # Synthetic topology only. Tests never load operator credentials or call APIs/SSH.
  def self.config(private_network = true, routing = true, cni = "cilium", host = "10.10.0.10", ip : String? = nil)
    node = {
      "host"                 => host,
      "ssh_user"             => "operator",
      "ssh_port"             => 2222,
      "ssh_private_key_path" => "/nonexistent/test-key",
      "manage_hostname"      => false,
      "index"                => 1,
    }
    node["ip"] = ip unless ip.nil?
    {
      "config_format_version" => 1,
      "hetzner_token"         => "",
      "cluster_name"          => "routing-test",
      "kubeconfig_path"       => "/nonexistent/kubeconfig",
      "k3s_version"           => "v1.35.0+k3s1",
      "networking"            => {
        "private_network" => {"enabled" => private_network, "external_routing" => routing, "subnet" => "10.20.0.0/16"},
        "public_network"  => {"use_local_firewall" => !private_network},
        "cni"             => {"enabled" => true, "mode" => cni, "encryption" => false},
      },
      "masters_pool"      => {"instance_type" => "cpx22", "instance_count" => 3},
      "worker_node_pools" => [{
        "name"           => "external-workers",
        "instance_type"  => "external",
        "instance_count" => 1,
        "external"       => {"provider" => "generic", "nodes" => [node]},
      }],
    }.to_yaml
  end

  def self.with_loader(yaml = config, &)
    File.tempfile("routing-spec", ".yaml") do |file|
      file.print(yaml)
      file.flush
      yield Configuration::Loader.new(file.path, nil, false)
    end
  end

  def self.errors(settings)
    errors = [] of String
    Configuration::Validators::ExternalRouting.new(errors, settings).validate
    settings.worker_node_pools.select(&.external?).each do |pool|
      Configuration::Validators::ExternalNodePool.new(errors, pool, settings).validate
    end
    errors
  end

  def self.master
    Hetzner::Instance.new(1, "running", "routing-test-master1", "10.20.0.5", "192.0.2.5")
  end

  class WorkerGenerator < Kubernetes::Script::WorkerGenerator
    private def generate_k3s_token(masters, first_master)
      "synthetic-test-token"
    end
  end

  class MasterGenerator < Kubernetes::Script::MasterGenerator
    private def generate_k3s_token(masters, first_master)
      "synthetic-test-token"
    end
  end

  class KubeconfigManager
    def generate_tls_sans(masters, first_master, load_balancer)
      ""
    end
  end

  class Run < Cluster::Run
    def ssh_target(instance)
      resolve_ssh_for_instance(instance, instance.host_ip_address.not_nil!)
    end
  end

  class RecordingSSH < Util::SSH
    getter commands = [] of String

    def run(instance, port, command, use_ssh_agent, print_output = true, disable_log_prefix = false, capture_output = false)
      @commands << command
      ""
    end
  end

  def self.worker_script(loader)
    pool = loader.settings.worker_node_pools.first
    WorkerGenerator.new(loader, loader.settings).generate_script([master], master, pool, pool.external.try(&.nodes.first?))
  end

  def self.master_script(loader)
    MasterGenerator.new(loader, loader.settings).generate_script(master, [master], master, nil, KubeconfigManager.new)
  end

  # Execute the actual generated shell with an inert installer and synthetic network
  # commands. Redirect every installer filesystem target into a disposable directory.
  # No real curl, ip, SSH, package installation or k3s command is executed.
  def self.install(script, host_ips = "192.0.2.10 10.10.0.10", addresses = "2: eth0 inet 192.0.2.10/24\n3: vpn0 inet 10.10.0.10/24\n4: enp7s0 inet 10.20.0.5/32\n")
    directory = File.tempname("routing-install-spec")
    Dir.mkdir(directory)
    begin
      script = script.gsub("/etc/initialized", "#{directory}/initialized")
        .gsub("/etc/rancher/k3s", "#{directory}/k3s")
        .gsub("/var/log/hetzner-k3s.log", "#{directory}/install.log")
      stubs = <<-'BASH'
        hostname() {
          if [ "$1" = "-I" ]; then printf '%s\n' "$TEST_HOST_IPS"; else echo test-worker; fi
        }
        ip() {
          if [ "$*" = '-o link show' ]; then
            echo '4: enp7s0: <UP> mtu 1450 state UP'
          elif [ "$*" = '-4 -o addr show dev enp7s0' ]; then
            printf '%s\n' "$TEST_ADDRESSES" | grep 'enp7s0 '
          elif [ "$*" = '-4 -o addr show' ]; then
            printf '%s\n' "$TEST_ADDRESSES"
          else
            echo "Unexpected ip command: $*" >&2
            return 1
          fi
        }
        curl() {
          case "$*" in
            *169.254.169.254*) echo 123 ;;
            *) echo '# inert installer' ;;
          esac
        }
        sh() { printf '%s\n' "$@" > "$TEST_INSTALL_ARGS"; }
        sleep() { echo 'Unexpected retry' >&2; exit 1; }
        BASH
      output = IO::Memory.new
      args_path = "#{directory}/args"
      status = Process.run("bash", ["-c", stubs + "\n" + script],
        env: {"TEST_HOST_IPS" => host_ips, "TEST_ADDRESSES" => addresses, "TEST_INSTALL_ARGS" => args_path},
        output: output, error: output)
      args = File.exists?(args_path) ? File.read_lines(args_path) : [] of String
      {success: status.success?, args: args, output: output.to_s}
    ensure
      FileUtils.rm_rf(directory)
    end
  end
end
