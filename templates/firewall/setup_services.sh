#!/bin/bash

# Setup systemd service
setup_systemd_services() {
    # Reload systemd, enable and start the service
    systemctl daemon-reload
    systemctl enable firewall_updater.service
    systemctl start firewall_updater.service

    systemctl enable ipset_restore.service
    systemctl enable iptables_restore.service

    echo "Firewall services have beem enabled and started"
    echo "Services status:"
    systemctl status firewall_updater.service --no-pager
}

# Create a symlink for the status script
create_status_symlink() {
    ln -sf /usr/local/lib/firewall/firewall_status.sh /usr/local/bin/firewall-status
    chmod +x /usr/local/bin/firewall-status
    echo "Created firewall status script at /usr/local/bin/firewall-status"
    echo "You can run 'sudo firewall-status' anytime to check your firewall configuration"
}

# Main execution
setup_systemd_services
create_status_symlink
