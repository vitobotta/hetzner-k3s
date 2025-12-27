require "base64"
require "crinja"
require "../../configuration/main"
require "../../hetzner/instance"
require "../../util/ssh"

class Kubernetes::LocalFirewall::Setup
  FIREWALL_SCRIPT  = {{ read_file("#{__DIR__}/../../../templates/firewall/firewall.sh") }}
  FIREWALL_SERVICE = {{ read_file("#{__DIR__}/../../../templates/firewall/firewall.service") }}
  FIREWALL_STATUS  = {{ read_file("#{__DIR__}/../../../templates/firewall/firewall_status.sh") }}

  private getter settings : Configuration::Main
  private getter ssh : ::Util::SSH

  def initialize(@settings, @ssh)
  end

  def deploy(instance : Hetzner::Instance) : Nil
    return unless local_firewall_enabled?

    log_line "Deploying local firewall...", instance
    deploy_firewall_files(instance)
    ensure_firewall_running(instance)
    log_line "Local firewall deployed", instance
  end

  private def local_firewall_enabled? : Bool
    !settings.networking.private_network.enabled && settings.networking.public_network.use_local_firewall
  end

  private def deploy_firewall_files(instance : Hetzner::Instance) : Nil
    firewall_script_b64 = Base64.strict_encode(render_firewall_script)
    firewall_service_b64 = Base64.strict_encode(FIREWALL_SERVICE)
    firewall_status_b64 = Base64.strict_encode(render_firewall_status)

    run_ssh(instance, <<-SCRIPT)
      echo '#{firewall_script_b64}' | base64 -d > /usr/local/bin/firewall.sh
      chmod 755 /usr/local/bin/firewall.sh

      echo '#{firewall_service_b64}' | base64 -d > /etc/systemd/system/firewall.service

      echo '#{firewall_status_b64}' | base64 -d > /usr/local/bin/firewall-status
      chmod 755 /usr/local/bin/firewall-status
    SCRIPT
  end

  private def ensure_firewall_running(instance : Hetzner::Instance) : Nil
    run_ssh(instance, <<-SCRIPT)
      if [ ! -f /etc/iptables/rules.v4 ]; then
        /usr/local/bin/firewall.sh setup
      fi
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
    })
  end

  private def render_firewall_status : String
    Crinja.render(FIREWALL_STATUS, {
      ssh_port: settings.networking.ssh.port,
    })
  end

  private def run_ssh(instance : Hetzner::Instance, script : String) : String
    ssh.run(instance, settings.networking.ssh.port, script, settings.networking.ssh.use_agent)
  end

  private def log_line(message : String, instance : Hetzner::Instance) : Nil
    puts "[Local Firewall - #{instance.name}] #{message}"
  end
end
