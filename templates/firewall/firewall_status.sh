#!/bin/bash

# Load environment variables
IPSET_NAME_API="allowed_networks_api"
IPSET_NAME_SSH="allowed_networks_ssh"
IPSET_NAME_K8S="allowed_networks_k8s"
API_NETWORKS_FILE="/etc/allowed-networks-api.conf"
SSH_NETWORKS_FILE="/etc/allowed-networks-ssh.conf"
SSH_PORT="{{ ssh_port }}"
K8S_PORT=6443

echo "===== Firewall Status Check ====="
echo

# Check if UFW is installed and active
if command -v ufw &> /dev/null; then
    ufw_status=$(ufw status | grep "Status:")
    echo "UFW Status: $ufw_status"

    if echo "$ufw_status" | grep -q "active"; then
        echo "WARNING: UFW is active and may conflict with direct iptables rules"
        echo "UFW Rules:"
        ufw status numbered
        echo
    fi
fi

# Check for allowed networks files
echo "===== Allowed Networks Files ====="
for file in "$API_NETWORKS_FILE" "$SSH_NETWORKS_FILE"; do
    if [ -f "$file" ]; then
        network_count=$(grep -v "^#" "$file" | grep -v "^$" | wc -l)
        echo "Found $(basename $file) with $network_count network ranges"
        echo "Network ranges:"
        grep -v "^#" "$file" | grep -v "^$" | head -10

        if [ "$network_count" -gt 10 ]; then
            echo "... and $(($network_count - 10)) more networks"
        fi
    else
        echo "No $(basename $file) file found"
    fi
    echo
done

# Check ipset status
echo "===== IPSET Status ====="
if command -v ipset &> /dev/null; then
    for ipset_name in "$IPSET_NAME_API" "$IPSET_NAME_SSH" "$IPSET_NAME_K8S"; do
        if ipset list -n | grep -q "^$ipset_name$"; then
            network_count=$(ipset list $ipset_name | grep "Number of entries:" | awk '{print $4}')
            ipset_type=$(ipset list $ipset_name | grep "Type:" | awk '{print $2}')

            if [ "$ipset_name" = "$IPSET_NAME_API" ]; then
                access_type="full access"
            elif [ "$ipset_name" = "$IPSET_NAME_K8S" ]; then
                access_type="port $K8S_PORT only"
            else
                access_type="SSH access"
            fi

            echo "Network Allowlist '$ipset_name' Status: Active with $network_count entries (Type: $ipset_type, $access_type)"
            echo "First 10 allowed entries (sample):"
            ipset list $ipset_name | grep -A 10 "Members:" | tail -10

            if [ "$network_count" -gt 10 ]; then
                echo "... and $(($network_count - 10)) more entries"
            fi
        else
            echo "Network Allowlist Status: Not found (ipset '$ipset_name' doesn't exist)"
        fi
        echo
    done
else
    echo "ipset command not found"
fi
echo

# Check iptables rules
echo "===== IPTABLES Rules ====="
if command -v iptables &> /dev/null; then
    # Check default policies
    echo "Default Policies:"
    iptables -L | grep "Chain" | head -3
    echo

    # Check for ICMP rule
    echo "Checking for ICMP (ping) rule:"
    if iptables -L INPUT -v | grep -q "ACCEPT.*icmp"; then
        echo "✓ FOUND: ICMP (ping) rule is active"
        iptables -L INPUT -v | grep "ACCEPT.*icmp"
    else
        echo "✗ NOT FOUND: ICMP (ping) rule is missing from iptables"
    fi
    echo

    # Check for our ipset rules
    echo "Checking for ipset rules:"
    if iptables -L INPUT -v | grep -q "match-set $IPSET_NAME_API"; then
        echo "✓ FOUND: API networks rule is active (allowing all traffic)"
        iptables -L INPUT -v | grep "match-set $IPSET_NAME_API"
    else
        echo "✗ NOT FOUND: API networks rule is missing from iptables"
    fi

    if iptables -L INPUT -v | grep -q "match-set $IPSET_NAME_K8S"; then
        echo "✓ FOUND: K8S networks rule is active (port $K8S_PORT only)"
        iptables -L INPUT -v | grep "match-set $IPSET_NAME_K8S"
    else
        echo "✗ NOT FOUND: K8S networks rule is missing from iptables"
    fi

    if iptables -L INPUT -v | grep -q "match-set $IPSET_NAME_SSH"; then
        echo "✓ FOUND: SSH networks rule is active (port $SSH_PORT)"
        iptables -L INPUT -v | grep "match-set $IPSET_NAME_SSH"
    else
        echo "✗ NOT FOUND: SSH networks rule is missing from iptables"
    fi
    echo

    # Show all INPUT rules
    echo "All INPUT Chain Rules:"
    iptables -L INPUT -v --line-numbers
else
    echo "iptables command not found"
fi
echo

# Check if our service is running
echo "===== Firewall Updater Service ====="
if systemctl list-unit-files | grep -q "firewall-updater.service"; then
    service_status=$(systemctl is-active firewall-updater.service)
    echo "Service Status: $service_status"

    if [ "$service_status" = "active" ]; then
        echo "Service Uptime:"
        systemctl status firewall-updater.service | grep "Active:"
        echo
        echo "Recent Logs:"
        journalctl -u firewall-updater.service --no-pager -n 10
    else
        echo "Service is not running!"
    fi
else
    echo "Firewall updater service not installed"
fi
