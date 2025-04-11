#!/bin/bash

# Main installation script for firewall setup
# This script coordinates the installation process

# Configuration variables
TOKEN="{{ hetzner_token }}"
HETZNER_IP_QUERY_SERVER_URL="{{ hetzner_ips_query_server_url }}/ips"
SSH_PORT="{{ ssh_port }}"
IPSET_NAME_NODES="nodes"
IPSET_NAME_SSH="allowed_networks_ssh"
IPSET_NAME_KUBERNETES_API="allowed_networks_k8s_api"
KUBERNETES_API_ALLOWED_NETWORKS_FILE="/etc/allowed-networks-kubernetes-api.conf"
SSH_ALLOWED_NETWORKS_FILE="/etc/allowed-networks-ssh.conf"
KUBERNETES_API_PORT=6443
MAX_RETRIES=3
RETRY_DELAY=5
IPSET_TYPE="hash:net"

# Check if script is run as root
if [ "$(id -u)" -ne 0 ]; then
    echo "This script must be run as root" >&2
    exit 1
fi

# Install required packages without prompting
install_packages() {
    echo "Installing required packages..."
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -qq
    apt-get install -y -qq jq ipset iptables-persistent curl
    echo "Required packages installed."
}

# Check and install required packages
for pkg in jq ipset curl; do
    if ! command -v $pkg &> /dev/null; then
        install_packages
        break
    fi
done

# Check for iptables-persistent
if ! dpkg -l | grep -q iptables-persistent; then
    # Pre-answer the prompt for saving current rules
    echo iptables-persistent iptables-persistent/autosave_v4 boolean true | debconf-set-selections
    echo iptables-persistent iptables-persistent/autosave_v6 boolean true | debconf-set-selections
    apt-get install -y -qq iptables-persistent
fi

# Create scripts directory if it doesn't exist
SCRIPTS_DIR="/usr/local/lib/firewall"
mkdir -p $SCRIPTS_DIR

# Export variables for use in other scripts
export TOKEN HETZNER_IP_QUERY_SERVER_URL SSH_PORT IPSET_NAME_NODES IPSET_NAME_SSH IPSET_NAME_KUBERNETES_API
export KUBERNETES_API_ALLOWED_NETWORKS_FILE SSH_ALLOWED_NETWORKS_FILE KUBERNETES_API_PORT MAX_RETRIES RETRY_DELAY IPSET_TYPE
export SCRIPTS_DIR

# Execute the component scripts
echo "Setting up scalable IP-based firewall..."
$SCRIPTS_DIR/configure_firewall.sh
$SCRIPTS_DIR/setup_service.sh

echo
echo "Setup complete! The firewall-updater service is now running."
echo "You can check its status with: sudo systemctl status firewall_updater.service"
echo "You can check the firewall configuration with: sudo firewall-status"
echo
echo "To add custom network ranges for API access (port $KUBERNETES_API_PORT only), create a file at: $KUBERNETES_API_ALLOWED_NETWORKS_FILE"
echo "To add custom network ranges for SSH access, create a file at: $SSH_ALLOWED_NETWORKS_FILE"
echo "Add one network range per line (e.g., 192.168.1.0/24)"
echo "The service will automatically include these ranges in the firewall."
echo
