#!/bin/bash

# Configuration
declare -A IPSETS=(
    ["nodes"]="nodes"
    ["allowed_networks_ssh"]="SSH access"
    ["allowed_networks_k8s_api"]="port 6443 only"
)

NETWORK_FILES=(
    "/etc/allowed-networks-kubernetes-api.conf"
    "/etc/allowed-networks-ssh.conf"
)

SSH_PORT="{{ ssh_port }}"
KUBERNETES_API_PORT=6443

# Helper functions
print_section() {
    echo "===== $1 ====="
    echo
}

check_command() {
    command -v "$1" &> /dev/null
}

print_limited_entries() {
    local count=$1
    local entries=$2
    local limit=10

    echo "$entries" | head -$limit
    if [ "$count" -gt $limit ]; then
        echo "... and $(($count - $limit)) more entries"
    fi
}

# Check UFW status
check_ufw_status() {
    print_section "UFW Status"
    if check_command ufw; then
        local status
        status=$(ufw status | grep "Status:")

        if echo "$status" | grep -q "inactive"; then
            echo "UFW Status: $status"
        else
            echo "WARNING: UFW is active and may conflict with direct iptables rules"
            ufw status numbered
        fi
    else
        echo "UFW not installed"
    fi
    echo
}

# Check network files
check_network_files() {
    print_section "Allowed Networks Files"
    for file in "${NETWORK_FILES[@]}"; do
        if [ -f "$file" ]; then
            local count
            count=$(grep -v "^#" "$file" | grep -v "^$" | wc -l)
            echo "Found $(basename "$file") with $count network ranges"
            echo "Network ranges:"
            print_limited_entries "$count" "$(grep -v '^#' "$file" | grep -v '^$')"
        else
            echo "No $(basename "$file") file found"
        fi
        echo
    done
}

# Check ipset status
check_ipset_status() {
    print_section "IPSET Status"
    if ! check_command ipset; then
        echo "ipset command not found"
        return
    fi

    for ipset_name in "${!IPSETS[@]}"; do
        if ipset list -n | grep -q "^$ipset_name$"; then
            local count type
            count=$(ipset list "$ipset_name" | grep "Number of entries:" | awk '{print $4}')
            type=$(ipset list "$ipset_name" | grep "Type:" | awk '{print $2}')

            echo "Network Allowlist '$ipset_name' Status: Active with $count entries (Type: $type, ${IPSETS[$ipset_name]})"
            echo "First 10 allowed entries (sample):"
            print_limited_entries "$count" "$(ipset list "$ipset_name" | grep -A 10 "Members:" | tail -10)"
        else
            echo "Network Allowlist Status: Not found (ipset '$ipset_name' doesn't exist)"
        fi
        echo
    done
}

# Check iptables rules
check_iptables_rules() {
    print_section "IPTABLES Rules"
    if ! check_command iptables; then
        echo "iptables command not found"
        return
    fi

    echo "Default Policies:"
    iptables -L | grep "Chain" | head -3
    echo

    # Check ICMP and ipset rules
    local rules=(
        "ICMP:ACCEPT.*icmp:✓ FOUND: ICMP (ping) rule is active:✗ NOT FOUND: ICMP (ping) rule is missing"
        "nodes:match-set nodes:✓ FOUND: API networks rule is active (allowing all traffic):✗ NOT FOUND: API networks rule is missing"
        "kubernetes_api:match-set allowed_networks_k8s_api:✓ FOUND: K8S networks rule is active (port $KUBERNETES_API_PORT only):✗ NOT FOUND: K8S networks rule is missing"
        "ssh:match-set allowed_networks_ssh:✓ FOUND: SSH networks rule is active (port $SSH_PORT):✗ NOT FOUND: SSH networks rule is missing"
    )

    for rule in "${rules[@]}"; do
        IFS=':' read -r name pattern success_msg fail_msg <<< "$rule"
        echo "Checking for $name rule:"
        if iptables -L INPUT -v | grep -q "$pattern"; then
            echo "$success_msg"
            iptables -L INPUT -v | grep "$pattern"
        else
            echo "$fail_msg"
        fi
        echo
    done

    echo "All INPUT Chain Rules:"
    iptables -L INPUT -v --line-numbers
}

# Check firewall service
check_firewall_service() {
    print_section "Firewall Updater Service"
    if systemctl list-unit-files | grep -q "firewall_updater.service"; then
        local status
        status=$(systemctl is-active firewall_updater.service)
        echo "Service Status: $status"

        if [ "$status" = "active" ]; then
            echo "Service Uptime:"
            systemctl status firewall_updater.service | grep "Active:"
            echo
            echo "Recent Logs:"
            journalctl -u firewall_updater.service --no-pager -n 10
        else
            echo "Service is not running!"
        fi
    else
        echo "Firewall updater service not installed"
    fi
}

# Main execution
main() {
    print_section "Firewall Status Check"
    check_ufw_status
    check_network_files
    check_ipset_status
    check_iptables_rules
    check_firewall_service
}

main