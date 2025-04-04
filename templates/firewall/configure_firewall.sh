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

    # Allow nodeport
    iptables -A INPUT -p tcp --match multiport --dports 30000:32767 -j ACCEPT

    # Allow traffic from pod network
    iptables -A INPUT -s {{ cluster_cidr }} -j ACCEPT

    # Allow traffic from service network
    iptables -A INPUT -s {{ service_cidr }} -j ACCEPT


    # Create ipsets for FULL, SSH, and KUBERNETES API access if they don't exist
    for IPSET_NAME in $IPSET_NAME_NODES $IPSET_NAME_SSH $IPSET_NAME_KUBERNETES_API; do
        # Remove existing ipset if it exists with wrong type
        if ipset list -n | grep -q "^$IPSET_NAME$"; then
            current_type=$(ipset list $IPSET_NAME | grep "Type:" | awk '{print $2}')
            if [ "$current_type" != "$IPSET_TYPE" ]; then
                echo "Existing ipset $IPSET_NAME has wrong type ($current_type). Recreating with correct type ($IPSET_TYPE)..."
                ipset destroy $IPSET_NAME
            fi
        fi

        # Create ipset if it doesn't exist
        if ! ipset list -n | grep -q "^$IPSET_NAME$"; then
            echo "Creating ipset $IPSET_NAME for allowed networks..."
            ipset create $IPSET_NAME $IPSET_TYPE hashsize 4096
        fi
    done

    # Allow all traffic between nodes
    if ! iptables -C INPUT -m set --match-set $IPSET_NAME_NODES src -j ACCEPT 2>/dev/null; then
        echo "Adding rule to allow all traffic between nodes..."
        iptables -A INPUT -m set --match-set $IPSET_NAME_NODES src -j ACCEPT
    fi

    # Allow only KUBERNETES API port (6443) from networks in KUBERNETES_API_ALLOWED_NETWORKS_FILE
    if ! iptables -C INPUT -p tcp --dport $KUBERNETES_API_PORT -m set --match-set $IPSET_NAME_KUBERNETES_API src -j ACCEPT 2>/dev/null; then
        echo "Adding rule to allow K8S API access (port $KUBERNETES_API_PORT) from K8S networks..."
        iptables -A INPUT -p tcp --dport $KUBERNETES_API_PORT -m set --match-set $IPSET_NAME_KUBERNETES_API src -j ACCEPT
    fi

    # Allow only SSH access from networks in SSH_ALLOWED_NETWORKS_FILE
    if ! iptables -C INPUT -p tcp --dport $SSH_PORT -m set --match-set $IPSET_NAME_SSH src -j ACCEPT 2>/dev/null; then
        echo "Adding SSH access rule to iptables..."
        iptables -A INPUT -p tcp --dport $SSH_PORT -m set --match-set $IPSET_NAME_SSH src -j ACCEPT
    fi

    # Save iptables rules
    if command -v netfilter-persistent &> /dev/null; then
        netfilter-persistent save
    else
        echo "WARNING: netfilter-persistent not found. Rules may not persist after reboot."
        if [ -d "/etc/iptables" ]; then
            iptables-save > /etc/iptables/rules.v4
            echo "Rules saved to /etc/iptables/rules.v4"
        fi
    fi

    echo "Firewall configured successfully."
}

# Save iptables rules and ipsets
save_rules() {
    echo "Saving iptables rules and ipsets..."
    # Save iptables rules
    iptables-save > /etc/iptables/rules.v4
    # Save ipsets
    ipset save > /etc/iptables/ipsets.v4
    echo "Rules and ipsets saved."
}

# Main execution
handle_ufw
setup_iptables
save_rules
