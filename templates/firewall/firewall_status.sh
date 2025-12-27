#!/bin/bash

# Firewall Status Script for hetzner-k3s

readonly SSH_PORT="{{ ssh_port }}"
readonly API_PORT=6443

readonly IPSETS=("nodes:Node IPs" "allowed_networks_ssh:SSH access" "allowed_networks_k8s_api:API access (port $API_PORT)")
readonly NETWORK_FILES=("/etc/allowed-networks-kubernetes-api.conf" "/etc/allowed-networks-ssh.conf")

print_section() {
    echo
    echo "===== $1 ====="
    echo
}

print_limited() {
    local count=$1
    local entries=$2
    local limit=10

    echo "$entries" | head -$limit
    if [ "$count" -gt $limit ]; then
        echo "... and $((count - limit)) more entries"
    fi
}

check_ufw() {
    print_section "UFW Status"
    if command -v ufw &>/dev/null; then
        local status
        status=$(ufw status 2>/dev/null | grep "Status:" || echo "Status: unknown")
        if echo "$status" | grep -q "inactive"; then
            echo "UFW: inactive (good)"
        else
            echo "WARNING: UFW may be active and could conflict with iptables"
            ufw status numbered 2>/dev/null
        fi
    else
        echo "UFW: not installed"
    fi
}

check_network_files() {
    print_section "Allowed Networks Configuration"
    for file in "${NETWORK_FILES[@]}"; do
        local basename
        basename=$(basename "$file")
        if [ -f "$file" ]; then
            local count
            count=$(grep -v "^#" "$file" 2>/dev/null | grep -v "^$" | wc -l)
            echo "$basename: $count networks configured"
            if [ "$count" -gt 0 ]; then
                print_limited "$count" "$(grep -v '^#' "$file" | grep -v '^$')"
            fi
        else
            echo "$basename: not found"
        fi
        echo
    done
}

check_ipsets() {
    print_section "IPSet Status"
    if ! command -v ipset &>/dev/null; then
        echo "ipset: not installed"
        return
    fi

    for entry in "${IPSETS[@]}"; do
        local name="${entry%%:*}"
        local desc="${entry#*:}"

        if ipset list -n 2>/dev/null | grep -q "^${name}$"; then
            local count
            count=$(ipset list "$name" 2>/dev/null | grep "Number of entries:" | awk '{print $4}')
            local type
            type=$(ipset list "$name" 2>/dev/null | grep "Type:" | awk '{print $2}')
            echo "$name ($desc): $count entries [type: $type]"

            if [ "$count" -gt 0 ]; then
                local entries
                entries=$(ipset list "$name" 2>/dev/null | sed -n '/^Members:/,$p' | tail -n +2)
                print_limited "$count" "$entries"
            fi
        else
            echo "$name ($desc): not found"
        fi
        echo
    done
}

check_iptables() {
    print_section "IPTables Rules"
    if ! command -v iptables &>/dev/null; then
        echo "iptables: not installed"
        return
    fi

    echo "Default Policies:"
    iptables -L 2>/dev/null | grep "^Chain" | head -3
    echo

    echo "Key Rules Check:"
    local checks=(
        "ICMP:icmp"
        "Nodes ipset:match-set nodes"
        "API ipset:match-set allowed_networks_k8s_api"
        "SSH ipset:match-set allowed_networks_ssh"
    )

    for check in "${checks[@]}"; do
        local name="${check%%:*}"
        local pattern="${check#*:}"
        if iptables -L INPUT -v 2>/dev/null | grep -q "$pattern"; then
            echo "  [OK] $name rule active"
        else
            echo "  [MISSING] $name rule"
        fi
    done

    echo
    echo "INPUT Chain (full):"
    iptables -L INPUT -v --line-numbers 2>/dev/null
}

check_service() {
    print_section "Firewall Service"
    if systemctl list-unit-files 2>/dev/null | grep -q "firewall.service"; then
        local status
        status=$(systemctl is-active firewall.service 2>/dev/null)
        echo "Service: $status"

        if [ "$status" = "active" ]; then
            systemctl status firewall.service --no-pager -l 2>/dev/null | grep -E "Active:|Main PID:"
            echo
            echo "Recent logs:"
            journalctl -u firewall.service --no-pager -n 5 2>/dev/null
        fi
    else
        echo "firewall.service: not installed"
    fi
}

main() {
    echo "========================================="
    echo "  hetzner-k3s Firewall Status Report"
    echo "========================================="

    check_ufw
    check_network_files
    check_ipsets
    check_iptables
    check_service

    echo
    echo "========================================="
}

main
