#!/bin/bash

# Setup systemd service
setup_systemd_services() {
    echo "Setting up systemd services..."

    # Reload systemd to recognize new services
    if ! systemctl daemon-reload; then
        echo "ERROR: Failed to reload systemd daemon"
        return 1
    fi

    # Enable and start the firewall updater service
    if systemctl enable firewall_updater.service && systemctl start firewall_updater.service; then
        echo "Firewall updater service enabled and started"
    else
        echo "ERROR: Failed to enable or start firewall updater service"
        return 1
    fi

    # Enable the restore services
    if systemctl enable ipset_restore.service && systemctl enable iptables_restore.service; then
        echo "Restore services enabled"
    else
        echo "ERROR: Failed to enable restore services"
        return 1
    fi

    echo "Firewall services have been enabled and started successfully"
    echo "Services status:"
    systemctl status firewall_updater.service --no-pager -l
}

# Create a symlink for the status script
create_status_symlink() {
    local source="/usr/local/lib/firewall/firewall_status.sh"
    local target="/usr/local/bin/firewall-status"

    echo "Creating symlink for firewall status script..."

    # Check if source file exists
    if [ ! -f "$source" ]; then
        echo "ERROR: Source file $source does not exist"
        return 1
    fi

    # Create symlink
    if ln -sf "$source" "$target"; then
        chmod +x "$target"
        echo "Created firewall status script at $target"
        echo "You can run 'sudo firewall-status' anytime to check your firewall configuration"
    else
        echo "ERROR: Failed to create symlink"
        return 1
    fi
}

# Main execution
main() {
    echo "Setting up firewall services..."

    if setup_systemd_services && create_status_symlink; then
        echo "Firewall services setup completed successfully"
    else
        echo "Firewall services setup failed"
        exit 1
    fi
}

# Run main function if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main
fi