#!/bin/bash
set -euo pipefail

# =============================================================================
# Unified Firewall Script for hetzner-k3s
# Handles initial setup, ongoing updates, and restoration on boot
# =============================================================================

# Configuration (injected via Crinja templating)
readonly HETZNER_TOKEN="{{ hetzner_token }}"
readonly HETZNER_IPS_URL="{{ hetzner_ips_query_server_url }}/ips"
readonly SSH_PORT="{{ ssh_port }}"
readonly CLUSTER_CIDR="{{ cluster_cidr }}"
readonly SERVICE_CIDR="{{ service_cidr }}"
readonly NODEPORT_RANGE="{{ node_port_range_iptables }}"
readonly NODEPORT_FIREWALL_ENABLED="{{ node_port_firewall_enabled }}"

# Constants
readonly IPSET_NODES="nodes"
readonly IPSET_SSH="allowed_networks_ssh"
readonly IPSET_API="allowed_networks_k8s_api"
readonly IPSET_TYPE="hash:net"
readonly API_PORT=6443
readonly POLL_INTERVAL=30
readonly API_TIMEOUT=10
readonly API_RETRIES=3
readonly API_RETRY_DELAY=5

readonly SSH_NETWORKS_FILE="/etc/allowed-networks-ssh.conf"
readonly API_NETWORKS_FILE="/etc/allowed-networks-kubernetes-api.conf"
readonly IPTABLES_RULES_FILE="/etc/iptables/rules.v4"
readonly IPSET_RULES_FILE="/etc/iptables/ipsets.v4"
readonly LAST_IPS_FILE="/tmp/last_node_ips.txt"

# =============================================================================
# Utility Functions
# =============================================================================

log() {
    echo "$*"
}

validate_ip_network() {
    [[ $1 =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+(/[0-9]+)?$ ]]
}

normalise_networks() {
    grep -v '^[[:space:]]*$' | \
    grep -v '^[[:space:]]*#' | \
    tr -d '\r' | \
    sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | \
    sed -E 's/^([0-9]+\.[0-9]+\.[0-9]+\.[0-9]+)$/\1\/32/' | \
    sort -u
}

# =============================================================================
# Package Installation
# =============================================================================

install_packages() {
    local packages_needed=false

    for pkg in jq ipset curl; do
        if ! command -v "$pkg" &>/dev/null; then
            packages_needed=true
            break
        fi
    done

    if ! dpkg -l | grep -q iptables-persistent; then
        packages_needed=true
    fi

    if $packages_needed; then
        log "Installing required packages..."
        export DEBIAN_FRONTEND=noninteractive
        echo iptables-persistent iptables-persistent/autosave_v4 boolean true | debconf-set-selections
        echo iptables-persistent iptables-persistent/autosave_v6 boolean true | debconf-set-selections
        apt-get update -qq
        apt-get install -y -qq jq ipset iptables-persistent curl
        log "Packages installed"
    fi
}

# =============================================================================
# UFW Handling
# =============================================================================

disable_ufw() {
    if command -v ufw &>/dev/null; then
        if ufw status 2>/dev/null | grep -q "Status: active"; then
            log "Disabling UFW to prevent conflicts..."
            ufw disable
        fi
    fi
}

# =============================================================================
# IPSet Management
# =============================================================================

create_ipset_if_missing() {
    local name=$1
    if ! ipset list -n 2>/dev/null | grep -q "^${name}$"; then
        ipset create "$name" "$IPSET_TYPE" hashsize 4096
        log "Created ipset: $name"
    fi
}

update_ipset() {
    local name=$1
    local networks=$2
    local temp_name="${name}_temp"

    # Get current networks
    local current=""
    if ipset list -n 2>/dev/null | grep -q "^${name}$"; then
        current=$(ipset list "$name" 2>/dev/null | sed -n '/^Members:/,$p' | tail -n +2 | normalise_networks)
    fi

    # Normalise new networks
    local new
    new=$(echo "$networks" | normalise_networks)

    # Check for changes
    if [ "$current" = "$new" ]; then
        return 0
    fi

    # Create temp ipset and populate
    ipset destroy "$temp_name" 2>/dev/null || true
    ipset create "$temp_name" "$IPSET_TYPE" hashsize 4096

    local count=0
    while IFS= read -r network; do
        if [ -n "$network" ] && validate_ip_network "$network"; then
            if ipset add "$temp_name" "$network" 2>/dev/null; then
                ((count++))
            fi
        fi
    done <<< "$new"

    # Swap or rename
    if ipset list -n 2>/dev/null | grep -q "^${name}$"; then
        ipset swap "$temp_name" "$name"
        ipset destroy "$temp_name" 2>/dev/null || true
    else
        ipset rename "$temp_name" "$name"
    fi

    log "Updated ipset '$name': $count entries"
}

save_ipsets() {
    mkdir -p "$(dirname "$IPSET_RULES_FILE")"
    ipset save > "$IPSET_RULES_FILE"
}

restore_ipsets() {
    if [ -f "$IPSET_RULES_FILE" ]; then
        ipset restore -f "$IPSET_RULES_FILE" 2>/dev/null || true
        log "Restored ipsets from $IPSET_RULES_FILE"
    fi
}

# =============================================================================
# IPTables Configuration
# =============================================================================

setup_iptables() {
    log "Configuring iptables..."

    # Flush INPUT chain and set defaults
    # Note: We only flush INPUT as other chains (FORWARD, etc.) are managed by K3s/CNI
    iptables -F INPUT
    iptables -P INPUT DROP
    iptables -P OUTPUT ACCEPT

    # Basic rules
    iptables -A INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
    iptables -A INPUT -i lo -j ACCEPT
    iptables -A INPUT -p icmp -j ACCEPT

    # NodePort range
    if [ "$NODEPORT_FIREWALL_ENABLED" = "true" ]; then
        iptables -A INPUT -p tcp --match multiport --dports $NODEPORT_RANGE -j ACCEPT
        iptables -A INPUT -p udp --match multiport --dports $NODEPORT_RANGE -j ACCEPT
    fi

    # Pod and service networks
    iptables -A INPUT -s "$CLUSTER_CIDR" -j ACCEPT
    iptables -A INPUT -s "$SERVICE_CIDR" -j ACCEPT

    # IPSet-based rules
    iptables -A INPUT -m set --match-set "$IPSET_NODES" src -j ACCEPT
    iptables -A INPUT -p tcp --dport $API_PORT -m set --match-set "$IPSET_API" src -j ACCEPT
    iptables -A INPUT -p tcp --dport "$SSH_PORT" -m set --match-set "$IPSET_SSH" src -j ACCEPT

    save_iptables
    log "iptables configured"
}

save_iptables() {
    mkdir -p "$(dirname "$IPTABLES_RULES_FILE")"
    iptables-save > "$IPTABLES_RULES_FILE"
}

restore_iptables() {
    if [ -f "$IPTABLES_RULES_FILE" ]; then
        iptables-restore -w < "$IPTABLES_RULES_FILE" 2>/dev/null || true
        log "Restored iptables from $IPTABLES_RULES_FILE"
    fi
}

# =============================================================================
# Hetzner API
# =============================================================================

fetch_node_ips() {
    local attempt=0

    while [ $attempt -lt $API_RETRIES ]; do
        local response
        response=$(curl -sf -m "$API_TIMEOUT" -H "Hetzner-Token: $HETZNER_TOKEN" "$HETZNER_IPS_URL" 2>/dev/null) || true

        if [ -n "$response" ] && echo "$response" | jq -e . >/dev/null 2>&1; then
            local ips
            ips=$(echo "$response" | jq -r '.[]' 2>/dev/null)
            if [ -n "$ips" ]; then
                echo "$ips"
                return 0
            fi
        fi

        ((attempt++))
        if [ $attempt -lt $API_RETRIES ]; then
            sleep $API_RETRY_DELAY
        fi
    done

    # Fall back to cached IPs
    if [ -f "$LAST_IPS_FILE" ]; then
        cat "$LAST_IPS_FILE"
    fi
    return 1
}

# =============================================================================
# Network File Reading
# =============================================================================

read_networks_file() {
    local file=$1
    if [ -f "$file" ]; then
        cat "$file" | normalise_networks
    fi
}

# =============================================================================
# Update Loop
# =============================================================================

update_ipsets() {
    # Fetch node IPs from Hetzner API
    local node_ips
    node_ips=$(fetch_node_ips)
    if [ -n "$node_ips" ]; then
        echo "$node_ips" > "$LAST_IPS_FILE"
    fi

    # Read allowed networks from config files
    local ssh_networks
    ssh_networks=$(read_networks_file "$SSH_NETWORKS_FILE")
    local api_networks
    api_networks=$(read_networks_file "$API_NETWORKS_FILE")

    # Update ipsets
    update_ipset "$IPSET_NODES" "$node_ips"
    update_ipset "$IPSET_SSH" "$ssh_networks"
    update_ipset "$IPSET_API" "$api_networks"

    # Save for persistence
    save_ipsets
}

run_update_loop() {
    log "Firewall daemon started (poll interval: ${POLL_INTERVAL}s)"
    while true; do
        update_ipsets || log "Warning: update_ipsets failed, will retry"
        sleep $POLL_INTERVAL
    done
}

# =============================================================================
# Initial Setup
# =============================================================================

initial_setup() {
    log "Starting firewall setup..."

    install_packages
    disable_ufw

    # Create ipsets first (iptables rules reference them)
    create_ipset_if_missing "$IPSET_NODES"
    create_ipset_if_missing "$IPSET_SSH"
    create_ipset_if_missing "$IPSET_API"

    # Initial population of ipsets
    update_ipsets

    # Setup iptables rules
    setup_iptables

    log "Firewall setup complete"
}

# =============================================================================
# Main Entry Point
# =============================================================================

main() {
    case "${1:-}" in
        setup)
            initial_setup
            ;;
        restore)
            restore_ipsets
            restore_iptables
            ;;
        update)
            update_ipsets
            ;;
        daemon)
            log "Starting firewall daemon..."
            restore_ipsets
            restore_iptables
            run_update_loop
            ;;
        *)
            # Default: setup then daemon mode
            if [ ! -f "$IPTABLES_RULES_FILE" ]; then
                initial_setup
            else
                restore_ipsets
                restore_iptables
            fi
            run_update_loop
            ;;
    esac
}

main "$@"
