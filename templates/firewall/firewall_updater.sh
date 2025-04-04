#!/bin/bash

# Common constants
readonly LAST_SUCCESSFUL_IPS_FILE="/tmp/last_successful_ips.json"
readonly DEFAULT_MAX_RETRIES=3
readonly DEFAULT_RETRY_DELAY=5

# Function to validate IP/network format
validate_ip_network() {
    local ip_net=$1
    [[ $ip_net =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+(/[0-9]+)?$ ]]
}

# Function to fetch IPs from API with retry logic
fetch_ips_from_api() {
    local retry_count=0
    local max_retries=${MAX_RETRIES:-$DEFAULT_MAX_RETRIES}
    local delay=${RETRY_DELAY:-$DEFAULT_RETRY_DELAY}

    # Validate required environment variables
    if [ -z "$TOKEN" ] || [ -z "$HETZNER_IP_QUERY_SERVER_URL" ]; then
        echo "Error: TOKEN or HETZNER_IP_QUERY_SERVER_URL environment variables are not set"
        return 1
    fi

    while [ $retry_count -lt $max_retries ]; do
        local response=$(curl -s -m 10 -H "Hetzner-Token: $TOKEN" "$HETZNER_IP_QUERY_SERVER_URL")

        # Validate JSON response and check for entries
        if echo "$response" | jq -e . >/dev/null 2>&1 && [ "$(echo "$response" | jq 'length')" -gt 0 ]; then
            echo "$response" > "$LAST_SUCCESSFUL_IPS_FILE"
            echo "$response"
            return 0
        fi

        ((retry_count++))
        [ $retry_count -lt $max_retries ] && sleep $delay
    done

    echo "API request failed after $max_retries attempts."
    return 1
}

# Function to manage ipset operations
manage_ipset() {
    local name=$1
    local temp_name="${name}_temp"
    local type=${IPSET_TYPE:-"hash:net"}
    local networks=$2
    local old_count=0

    # Get current count
    if ipset list -n 2>/dev/null | grep -q "^$name$"; then
        old_count=$(ipset list "$name" | grep 'Number of entries:' | awk '{print $4}')
    fi

    # Create temporary ipset
    ipset destroy "$temp_name" 2>/dev/null || true
    ipset create "$temp_name" "$type"

    # Add networks to temporary ipset
    local new_count=0
    while IFS= read -r network; do
        if [ -n "$network" ] && validate_ip_network "$network"; then
            ipset add "$temp_name" "$network" 2>/dev/null && ((new_count++))
        fi
    done <<< "$networks"

    # Update main ipset
    if [ $new_count -gt 0 ]; then
        if ipset list -n 2>/dev/null | grep -q "^$name$"; then
            ipset swap "$temp_name" "$name"
        else
            ipset rename "$temp_name" "$name"
        fi
    fi
    ipset destroy "$temp_name" 2>/dev/null || true

    # Report changes
    echo "Current $name networks count: $new_count"
    if [ $old_count -ne $new_count ]; then
        local diff=$((new_count - old_count))
        [ $diff -gt 0 ] && echo "Added $diff new networks" || echo "Removed $((diff * -1)) networks"
    fi
}

# Function to read networks from file
read_networks_from_file() {
    local file=$1
    [ -f "$file" ] && grep -v '^[[:space:]]*#' "$file" | grep -v '^[[:space:]]*$' || echo ""
}

# Main update function
update_allowed_networks() {
    # Initialize default values
    local IPSET_NAME_NODES=${IPSET_NAME_NODES:-"nodes"}
    local IPSET_NAME_SSH=${IPSET_NAME_SSH:-"allowed_networks_ssh"}
    local IPSET_NAME_KUBERNETES_API=${IPSET_NAME_KUBERNETES_API:-"allowed_networks_k8s_api"}
    local KUBERNETES_API_ALLOWED_NETWORKS_FILE=${KUBERNETES_API_ALLOWED_NETWORKS_FILE:-"/etc/allowed-networks-kubernetes-api.conf"}
    local SSH_ALLOWED_NETWORKS_FILE=${SSH_ALLOWED_NETWORKS_FILE:-"/etc/allowed-networks-ssh.conf"}

    # Fetch networks from API
    local api_networks=$(fetch_ips_from_api)
    [ $? -eq 0 ] && api_networks=$(echo "$api_networks" | jq -r '.[]') || api_networks=""

    # Update ipsets
    manage_ipset "$IPSET_NAME_NODES" "$api_networks"
    manage_ipset "$IPSET_NAME_SSH" "$(read_networks_from_file "$SSH_ALLOWED_NETWORKS_FILE")"
    manage_ipset "$IPSET_NAME_KUBERNETES_API" "$(read_networks_from_file "$KUBERNETES_API_ALLOWED_NETWORKS_FILE")"
}

# Main loop
echo "Starting continuous firewall rule updates..."
while true; do
    echo "===== $(date '+%Y-%m-%d %H:%M:%S') ====="
    update_allowed_networks
    echo "-------------------------------------"
    sleep 5
done
