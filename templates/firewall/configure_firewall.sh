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


    # Create ipsets for API, SSH, and K8S access if they don't exist
    for IPSET_NAME in $IPSET_NAME_API $IPSET_NAME_SSH $IPSET_NAME_K8S; do
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

    # Allow all traffic from API networks (from API_URL)
    if ! iptables -C INPUT -m set --match-set $IPSET_NAME_API src -j ACCEPT 2>/dev/null; then
        echo "Adding rule to allow all traffic from API networks..."
        iptables -A INPUT -m set --match-set $IPSET_NAME_API src -j ACCEPT
    fi

    # Allow only K8S API port (6443) from K8S networks (from API_NETWORKS_FILE)
    if ! iptables -C INPUT -p tcp --dport $K8S_PORT -m set --match-set $IPSET_NAME_K8S src -j ACCEPT 2>/dev/null; then
        echo "Adding rule to allow K8S API access (port $K8S_PORT) from K8S networks..."
        iptables -A INPUT -p tcp --dport $K8S_PORT -m set --match-set $IPSET_NAME_K8S src -j ACCEPT
    fi

    # For SSH access only from specific networks
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

# Create a script to restore the ipset and iptables rule on boot
create_boot_script() {
    cat > /etc/network/if-pre-up.d/ipset-restore << EOF
#!/bin/bash
ipset create $IPSET_NAME_API $IPSET_TYPE hashsize 4096 2>/dev/null || true
ipset create $IPSET_NAME_SSH $IPSET_TYPE hashsize 4096 2>/dev/null || true
ipset create $IPSET_NAME_K8S $IPSET_TYPE hashsize 4096 2>/dev/null || true

iptables -P INPUT DROP
iptables -P FORWARD DROP
iptables -P OUTPUT ACCEPT

iptables -A INPUT -p tcp --match multiport --dports 30000:32767 -j ACCEPT

# Allow ICMP (ping) from any host
iptables -C INPUT -p icmp -j ACCEPT 2>/dev/null || iptables -A INPUT -p icmp -j ACCEPT

# Allow nodeport
iptables -A INPUT -p tcp --match multiport --dports 30000:32767 -j ACCEPT

# Allow traffic from pod network
iptables -A INPUT -s {{ cluster_cidr }} -j ACCEPT

# Allow traffic from service network
iptables -A INPUT -s {{ service_cidr }} -j ACCEPT

# Allow all traffic from API networks (from API_URL)
iptables -C INPUT -m set --match-set $IPSET_NAME_API src -j ACCEPT 2>/dev/null || iptables -A INPUT -m set --match-set $IPSET_NAME_API src -j ACCEPT

# Allow only K8S API port (6443) from K8S networks (from API_NETWORKS_FILE)
iptables -C INPUT -p tcp --dport $K8S_PORT -m set --match-set $IPSET_NAME_K8S src -j ACCEPT 2>/dev/null || iptables -A INPUT -p tcp --dport $K8S_PORT -m set --match-set $IPSET_NAME_K8S src -j ACCEPT

# For SSH access
iptables -C INPUT -p tcp --dport $SSH_PORT -m set --match-set $IPSET_NAME_SSH src -j ACCEPT 2>/dev/null || iptables -A INPUT -p tcp --dport $SSH_PORT -m set --match-set $IPSET_NAME_SSH src -j ACCEPT

exit 0
EOF
    chmod +x /etc/network/if-pre-up.d/ipset-restore
    echo "Created boot script for ipset and iptables restoration"
}

# Main execution
handle_ufw
setup_iptables
create_boot_script
