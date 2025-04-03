#!/bin/bash

# Setup systemd service
setup_systemd_service() {
    # Create a systemd service for the updater
    cat > /etc/systemd/system/firewall-updater.service << EOFS
[Unit]
Description=Firewall IP Updater Service
After=network.target

[Service]
Type=simple
ExecStart=/usr/local/lib/firewall/firewall_updater.sh
Restart=always
RestartSec=5
Environment="TOKEN={{ hetzner_token }}"
Environment="API_URL={{ ips_query_server_url }}/ips"
Environment="SSH_PORT={{ ssh_port }}"
Environment="IPSET_NAME_API=allowed_networks_api"
Environment="IPSET_NAME_SSH=allowed_networks_ssh"
Environment="IPSET_NAME_K8S=allowed_networks_k8s"
Environment="API_NETWORKS_FILE=/etc/allowed-networks-api.conf"
Environment="SSH_NETWORKS_FILE=/etc/allowed-networks-ssh.conf"
Environment="K8S_PORT=6443"
Environment="MAX_RETRIES=3"
Environment="RETRY_DELAY=5"
Environment="IPSET_TYPE=hash:net"

[Install]
WantedBy=multi-user.target
EOFS

    # Reload systemd, enable and start the service
    systemctl daemon-reload
    systemctl enable firewall-updater.service
    systemctl start firewall-updater.service

    echo "Firewall updater service has been enabled and started"
    echo "Service status:"
    systemctl status firewall-updater.service --no-pager
}

# Create a symlink for the status script
create_status_symlink() {
    ln -sf /usr/local/lib/firewall/firewall_status.sh /usr/local/bin/firewall-status
    chmod +x /usr/local/bin/firewall-status
    echo "Created firewall status script at /usr/local/bin/firewall-status"
    echo "You can run 'sudo firewall-status' anytime to check your firewall configuration"
}

# Main execution
setup_systemd_service
create_status_symlink
