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
    local current_networks=""
    local has_changes=false

    # Get current count and networks
    if ipset list -n 2>/dev/null | grep -q "^$name$"; then
        old_count=$(ipset list "$name" | grep 'Number of entries:' | awk '{print $4}')
        # Extract current networks from the existing ipset
        current_networks=$(ipset list "$name" | grep -A "$old_count" "Members:" | tail -n "$old_count" | sed 's/ comment.*$//')
    fi

    # Normalize IP addresses - explicitly add /32 to any bare IPv4 addresses
    normalize_ip() {
        sed -E 's/([0-9]+\.[0-9]+\.[0-9]+\.[0-9]+)$/\1\/32/g'
    }

    # Force identical format for both inputs
    standardize_networks() {
        grep -v '^[[:space:]]*$' | \
        tr -d '\r' | \
        sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | \
        normalize_ip | \
        sort
    }

    local new_networks_clean=$(echo "$networks" | standardize_networks)
    local current_networks_clean=$(echo "$current_networks" | standardize_networks)

    # Store standardized networks in files for debugging
    echo "$new_networks_clean" > "/tmp/${name}_new.txt"
    echo "$current_networks_clean" > "/tmp/${name}_current.txt"

    # Calculate hash with explicit removal of all newlines
    local new_hash=$(echo "$new_networks_clean" | tr -d '\n' | sha256sum | cut -d' ' -f1)
    local current_hash=$(echo "$current_networks_clean" | tr -d '\n' | sha256sum | cut -d' ' -f1)

    # Do a direct content comparison
    local direct_diff=$(diff <(echo "$new_networks_clean") <(echo "$current_networks_clean") 2>/dev/null)

    # Check if both network lists are empty - if so, no changes needed
    if [ -z "$new_networks_clean" ] && [ -z "$current_networks_clean" ]; then
        has_changes=false
    # Check direct diff first, then hash
    elif [ -n "$direct_diff" ]; then
        has_changes=true
    elif [ "$new_hash" != "$current_hash" ]; then
        has_changes=true
        echo "[$name] Changes detected (hash mismatch)"
    else
        echo "[$name] No changes detected for $name networks (count: $old_count)"
    fi

    # Only proceed with updates if there are changes
    if $has_changes; then
        # Create temporary ipset
        ipset destroy "$temp_name" 2>/dev/null || true
        ipset create "$temp_name" "$type"

        # Add networks to temporary ipset
        local new_count=0
        while IFS= read -r network; do
            if [ -n "$network" ] && validate_ip_network "$network"; then
                ipset add "$temp_name" "$network" 2>/dev/null && ((new_count++))
            fi
        done <<< "$new_networks_clean"

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
        echo "[$name] Updated $name networks. Current count: $new_count"
        if [ $old_count -ne $new_count ]; then
            local diff=$((new_count - old_count))
            [ $diff -gt 0 ] && echo "[$name] Added $diff new networks" || echo "[$name] Removed $((diff * -1)) networks"
        fi
    fi
}

# Function to read networks from file - ensure consistent output format
read_networks_from_file() {
    local file=$1
    if [ -f "$file" ]; then
        # Use a simpler, more direct approach
        grep -v '^[[:space:]]*#' "$file" | \
        grep -v '^[[:space:]]*$' | \
        tr -d '\r' | \
        sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | \
        sort
    else
        # Return empty with no newlines
        echo -n ""
    fi
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
    if [ $? -eq 0 ]; then
        api_networks=$(echo "$api_networks" | jq -r '.[]' | tr -d '\r' | sort)
    else
        api_networks=""
    fi

    # Read networks from files
    local ssh_networks=$(read_networks_from_file "$SSH_ALLOWED_NETWORKS_FILE")
    local k8s_api_networks=$(read_networks_from_file "$KUBERNETES_API_ALLOWED_NETWORKS_FILE")

    # Update ipsets
    manage_ipset "$IPSET_NAME_NODES" "$api_networks"
    manage_ipset "$IPSET_NAME_SSH" "$ssh_networks"
    manage_ipset "$IPSET_NAME_KUBERNETES_API" "$k8s_api_networks"
}

# Main loop
echo "Starting continuous firewall rule updates..."
while true; do
    echo "===== $(date '+%Y-%m-%d %H:%M:%S') ====="
    update_allowed_networks
    echo "-------------------------------"
    sleep 5
done
