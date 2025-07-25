#!/bin/bash

# Handle UFW automatically (disable if active)
handle_ufw() {
    if command -v ufw &> /dev/null; then
        if ufw status | grep -q "Status: active"; then
            echo "UFW is active. Disabling to prevent conflicts..."
            ufw disable
            echo "UFW disabled."
        else
            echo "UFW is installed but not active. No action needed."
        fi
    else
        echo "UFW not installed. Proceeding with iptables configuration."
    fi
}

# Configure iptables default policies
setup_iptables() {
    echo "Configuring iptables default policies..."

    # Clear existing rules and set default policies
    iptables -F
    iptables -X
    iptables -P INPUT DROP
    iptables -P FORWARD DROP
    iptables -P OUTPUT ACCEPT

    # Allow established and related connections
    iptables -A INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT

    # Allow loopback
    iptables -A INPUT -i lo -j ACCEPT

    # Allow ICMP (ping) from any host
    iptables -A INPUT -p icmp -j ACCEPT
    echo "Allowing ICMP (ping) from any host"

    # Allow nodeport range
    iptables -A INPUT -p tcp --match multiport --dports 30000:32767 -j ACCEPT

    # Allow traffic from pod network
    iptables -A INPUT -s {{ cluster_cidr }} -j ACCEPT

    # Allow traffic from service network
    iptables -A INPUT -s {{ service_cidr }} -j ACCEPT

    # Setup ipsets for access control
    setup_ipsets

    # Allow all traffic between nodes
    iptables -A INPUT -m set --match-set $IPSET_NAME_NODES src -j ACCEPT

    # Allow only KUBERNETES API port (6443) from networks in KUBERNETES_API_ALLOWED_NETWORKS_FILE
    iptables -A INPUT -p tcp --dport $KUBERNETES_API_PORT -m set --match-set $IPSET_NAME_KUBERNETES_API src -j ACCEPT

    # Allow only SSH access from networks in SSH_ALLOWED_NETWORKS_FILE
    iptables -A INPUT -p tcp --dport $SSH_PORT -m set --match-set $IPSET_NAME_SSH src -j ACCEPT

    # Save iptables rules
    save_iptables_rules

    echo "Firewall configured successfully."
}

# Setup ipsets for access control
setup_ipsets() {
    echo "Setting up ipsets for access control..."

    # Define ipsets to create
    IPSETS=("$IPSET_NAME_NODES" "$IPSET_NAME_SSH" "$IPSET_NAME_KUBERNETES_API")

    for IPSET_NAME in "${IPSETS[@]}"; do
        # Check if ipset exists with correct type
        if ipset list -n | grep -q "^$IPSET_NAME$"; then
            current_type=$(ipset list "$IPSET_NAME" | grep "Type:" | awk '{print $2}')
            if [ "$current_type" != "$IPSET_TYPE" ]; then
                echo "Recreating ipset $IPSET_NAME with correct type ($IPSET_TYPE)..."
                ipset destroy "$IPSET_NAME"
                ipset create "$IPSET_NAME" "$IPSET_TYPE" hashsize 4096
            fi
        else
            echo "Creating ipset $IPSET_NAME..."
            ipset create "$IPSET_NAME" "$IPSET_TYPE" hashsize 4096
        fi
    done
}

# Save iptables rules
save_iptables_rules() {
    echo "Saving iptables rules..."

    # Try to save using netfilter-persistent first
    if command -v netfilter-persistent &> /dev/null; then
        netfilter-persistent save
        return 0
    fi

    # Fallback to manual saving
    if [ -d "/etc/iptables" ]; then
        iptables-save > /etc/iptables/rules.v4
        echo "Rules saved to /etc/iptables/rules.v4"
        return 0
    fi

    echo "WARNING: Could not save iptables rules. Rules may not persist after reboot."
    return 1
}

# Save ipsets
save_ipsets() {
    echo "Saving ipsets..."
    if [ -d "/etc/iptables" ]; then
        ipset save > /etc/iptables/ipsets.v4
        echo "Ipsets saved to /etc/iptables/ipsets.v4"
    else
        echo "WARNING: Could not save ipsets. They may not persist after reboot."
    fi
}

# Main execution
main() {
    handle_ufw
    setup_iptables
    save_ipsets
}

# Run main function
main