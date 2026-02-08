require "base64"
require "crinja"
require "tasker"
require "../../configuration/main"
require "../../hetzner/instance"
require "../../util/ssh"

class Kubernetes::LocalFirewall::Setup
  FIREWALL_SCRIPT  = {{ read_file("#{__DIR__}/../../../templates/firewall/firewall.sh") }}
  FIREWALL_SERVICE = {{ read_file("#{__DIR__}/../../../templates/firewall/firewall.service") }}
  FIREWALL_STATUS  = {{ read_file("#{__DIR__}/../../../templates/firewall/firewall_status.sh") }}

  AUTOSCALED_NODE_TIMEOUT = 30.seconds

  private getter settings : Configuration::Main
  private getter ssh : ::Util::SSH

  def initialize(@settings, @ssh)
  end

  def deploy(instance : Hetzner::Instance) : Nil
    return unless local_firewall_enabled?

    log_line "Deploying local firewall...", instance.name
    deploy_firewall_files(instance)
    ensure_firewall_running(instance)
    log_line "...local firewall deployed", instance.name
  end

  def deploy_to_all_nodes(first_master : Hetzner::Instance, known_instances : Array(Hetzner::Instance)) : Nil
    return unless local_firewall_enabled?

    all_node_ips = fetch_all_node_ips(first_master)
    return if all_node_ips.empty?

    known_ips = known_instances.flat_map { |i| [i.public_ip_address, i.private_ip_address].compact }
    autoscaled_ips = all_node_ips - known_ips

    return if autoscaled_ips.empty?

    log_line "Deploying firewall to #{autoscaled_ips.size} autoscaled node(s)..."

    completed_channel = Channel(String).new
    semaphore = Channel(Nil).new(10)

    autoscaled_ips.each do |ip|
      semaphore.send(nil)
      spawn do
        begin
          Tasker.timeout(AUTOSCALED_NODE_TIMEOUT) do
            instance = create_instance_from_ip(ip)
            deploy_firewall_files(instance)
            ensure_firewall_running(instance)
          end
        rescue Tasker::Timeout
          log_line "Timeout deploying firewall to #{ip}, skipping"
        rescue e : Exception
          log_line "Failed to deploy firewall to #{ip}: #{e.message}"
        ensure
          semaphore.receive
          completed_channel.send(ip)
        end
      end
    end

    autoscaled_ips.size.times { completed_channel.receive }
    log_line "...firewall deployed to all autoscaled nodes"
  end

  private def local_firewall_enabled? : Bool
    !settings.networking.private_network.enabled && settings.networking.public_network.use_local_firewall
  end

  private def deploy_firewall_files(instance : Hetzner::Instance) : Nil
    firewall_script_b64 = Base64.strict_encode(render_firewall_script)
    firewall_service_b64 = Base64.strict_encode(FIREWALL_SERVICE)
    firewall_status_b64 = Base64.strict_encode(render_firewall_status)
    ssh_networks_b64 = Base64.strict_encode(allowed_ssh_networks)
    api_networks_b64 = Base64.strict_encode(allowed_api_networks)

    run_ssh(instance, <<-SCRIPT)
      # Remove old firewall-status symlink if it exists (old version used a symlink)
      if [ -L /usr/local/bin/firewall-status ]; then
        rm -f /usr/local/bin/firewall-status
      fi

      echo '#{firewall_script_b64}' | base64 -d > /usr/local/bin/firewall.sh
      chmod 755 /usr/local/bin/firewall.sh

      echo '#{firewall_service_b64}' | base64 -d > /etc/systemd/system/firewall.service

      echo '#{firewall_status_b64}' | base64 -d > /usr/local/bin/firewall-status
      chmod 755 /usr/local/bin/firewall-status

      echo '#{ssh_networks_b64}' | base64 -d > /etc/allowed-networks-ssh.conf
      echo '#{api_networks_b64}' | base64 -d > /etc/allowed-networks-kubernetes-api.conf
    SCRIPT
  end

  private def ensure_firewall_running(instance : Hetzner::Instance) : Nil
    run_ssh(instance, <<-SCRIPT)
      # Stop and disable old firewall services if they exist
      for svc in firewall_updater iptables_restore ipset_restore; do
        if systemctl list-unit-files | grep -q "${svc}.service"; then
          systemctl stop ${svc}.service 2>/dev/null || true
          systemctl disable ${svc}.service 2>/dev/null || true
        fi
      done

      # Remove old firewall scripts if they exist
      rm -rf /usr/local/lib/firewall 2>/dev/null || true

      # Setup and start new firewall service
      /usr/local/bin/firewall.sh setup
      systemctl daemon-reload
      systemctl enable firewall.service
      systemctl restart firewall.service
    SCRIPT
  end

  private def render_firewall_script : String
    Crinja.render(FIREWALL_SCRIPT, {
      hetzner_token:                settings.hetzner_token,
      hetzner_ips_query_server_url: settings.networking.public_network.hetzner_ips_query_server_url,
      ssh_port:                     settings.networking.ssh.port,
      cluster_cidr:                 settings.networking.cluster_cidr,
      service_cidr:                 settings.networking.service_cidr,
      node_port_range_iptables:     settings.networking.node_port_range_iptables,
      node_port_firewall_enabled:   settings.networking.node_port_firewall_enabled,
    })
  end

  private def render_firewall_status : String
    Crinja.render(FIREWALL_STATUS, {
      ssh_port: settings.networking.ssh.port,
    })
  end

  private def allowed_ssh_networks : String
    settings.networking.allowed_networks.ssh.join("\n")
  end

  private def allowed_api_networks : String
    settings.networking.allowed_networks.api.join("\n")
  end

  private def run_ssh(instance : Hetzner::Instance, script : String) : String
    ssh.run(instance, settings.networking.ssh.port, script, settings.networking.ssh.use_agent)
  end

  private def fetch_all_node_ips(first_master : Hetzner::Instance) : Array(String)
    output = run_ssh(first_master, <<-SCRIPT)
      KUBECONFIG=/etc/rancher/k3s/k3s.yaml kubectl get nodes -o jsonpath='{range .items[*]}{.status.addresses[?(@.type=="ExternalIP")].address}{"\\n"}{end}' 2>/dev/null || true
    SCRIPT

    output.lines.map(&.strip).reject(&.empty?)
  end

  private def create_instance_from_ip(ip : String) : Hetzner::Instance
    Hetzner::Instance.new(
      id: 0,
      status: "running",
      instance_name: ip,
      internal_ip: ip,
      external_ip: ip
    )
  end

  private def log_line(message : String, instance_name : String? = nil) : Nil
    prefix = instance_name ? "Local Firewall - #{instance_name}" : "Local Firewall"
    puts "[#{prefix}] #{message}"
  end
end
