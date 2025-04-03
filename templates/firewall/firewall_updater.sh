#!/bin/bash

# Function to validate IP/network format
validate_ip_network() {
    local ip_net=$1

    # Check if it's a valid IP or network range
    if [[ $ip_net =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+(/[0-9]+)?$ ]]; then
        return 0
    else
        return 1
    fi
}

# Function to fetch IPs from API with retry logic
fetch_ips_from_api() {
    local retry_count=0
    local max_retries=${MAX_RETRIES:-3}  # Default to 3 if not set
    local delay=${RETRY_DELAY:-5}        # Default to 5 if not set
    local response=""
    local LAST_SUCCESSFUL_IPS_FILE="/tmp/last_successful_ips.json"

    # Check if TOKEN and API_URL are set
    if [ -z "$TOKEN" ] || [ -z "$API_URL" ]; then
        echo "Error: TOKEN or API_URL environment variables are not set"
        return 1
    fi

    while [ $retry_count -lt $max_retries ]; do
        # Attempt to fetch IPs with timeout
        response=$(curl -s -m 10 -H "Hetzner-Token: $TOKEN" "$API_URL")

        # Check if response is valid JSON
        if ! echo "$response" | jq -e . >/dev/null 2>&1; then
            retry_count=$((retry_count + 1))
            if [ $retry_count -lt $max_retries ]; then
                sleep $delay
            fi
            continue
        fi

        # Check if response has any entries
        ip_count=$(echo "$response" | jq 'length')

        if [ "$ip_count" -gt 0 ]; then
            # Success - save the response and return it
            echo "$response" > "$LAST_SUCCESSFUL_IPS_FILE"
            echo "$response"
            return 0
        else
            retry_count=$((retry_count + 1))
            if [ $retry_count -lt $max_retries ]; then
                sleep $delay
            fi
        fi
    done

    # All retries failed, return empty response
    echo "API request failed after $max_retries attempts."
    echo ""
    return 1
}

# Function to update allowed networks in ipset
update_allowed_networks() {
    local LAST_SUCCESSFUL_IPS_FILE="/tmp/last_successful_ips.json"

    # Set default values for environment variables if not set
    IPSET_NAME_API=${IPSET_NAME_API:-"allowed_networks_api"}
    IPSET_NAME_SSH=${IPSET_NAME_SSH:-"allowed_networks_ssh"}
    IPSET_NAME_K8S=${IPSET_NAME_K8S:-"allowed_networks_k8s"}
    API_NETWORKS_FILE=${API_NETWORKS_FILE:-"/etc/allowed-networks-api.conf"}
    SSH_NETWORKS_FILE=${SSH_NETWORKS_FILE:-"/etc/allowed-networks-ssh.conf"}
    K8S_PORT=${K8S_PORT:-6443}
    IPSET_TYPE=${IPSET_TYPE:-"hash:net"}

    echo "Using the following configuration:"
    echo "IPSET_NAME_API: $IPSET_NAME_API"
    echo "IPSET_NAME_SSH: $IPSET_NAME_SSH"
    echo "IPSET_NAME_K8S: $IPSET_NAME_K8S"
    echo "API_NETWORKS_FILE: $API_NETWORKS_FILE"
    echo "SSH_NETWORKS_FILE: $SSH_NETWORKS_FILE"
    echo "K8S_PORT: $K8S_PORT"
    echo "IPSET_TYPE: $IPSET_TYPE"

    # Get IPs from API with retry logic for API access
    response=$(fetch_ips_from_api)
    api_success=$?

    # If API request failed, try to use cached IPs
    if [ $api_success -ne 0 ]; then
        if [ -f "$LAST_SUCCESSFUL_IPS_FILE" ]; then
            echo "Using cached networks from last successful request"
            response=$(cat "$LAST_SUCCESSFUL_IPS_FILE")

            # Check if cached response is valid
            if ! echo "$response" | jq -e . >/dev/null 2>&1; then
                echo "Error: Cached response is invalid. Continuing with only network ranges."
                response='[]'
            fi
        else
            echo "No cached networks available. Continuing with only network ranges."
            response='[]'
        fi
    fi

    if ! networks=$(echo "$response" | jq -r '.[]' 2>/tmp/jq_error); then
        echo "ERROR: Failed to parse JSON response with jq"
        echo "jq error output:"
        cat /tmp/jq_error
        echo "Full API response:"
        echo "$response"
        networks=""
    else
        echo "DEBUG: Successfully parsed JSON response"
    fi

    # Extract IPs from JSON array and show them
    echo "DEBUG: Extracted networks:"
    echo "$networks"

    # Count the number of networks received
    if [ -z "$networks" ]; then
        network_count=0
        echo "Using 0 networks from API"
    else
        network_count=$(echo "$networks" | wc -l)
        echo "Using $network_count networks from API"
    fi

    # Initialize count variables
    old_count_api=0
    old_count_ssh=0
    old_count_k8s=0

    # Get current ipset counts before update
    if ipset list -n 2>/dev/null | grep -q "^$IPSET_NAME_API$"; then
        old_count_api=$(ipset list $IPSET_NAME_API | grep 'Number of entries:' | awk '{print $4}')
        # Ensure it's a number
        if ! [[ "$old_count_api" =~ ^[0-9]+$ ]]; then
            echo "Warning: old_count_api is not a number: '$old_count_api', setting to 0"
            old_count_api=0
        fi
    fi

    if ipset list -n 2>/dev/null | grep -q "^$IPSET_NAME_SSH$"; then
        old_count_ssh=$(ipset list $IPSET_NAME_SSH | grep 'Number of entries:' | awk '{print $4}')
        # Ensure it's a number
        if ! [[ "$old_count_ssh" =~ ^[0-9]+$ ]]; then
            echo "Warning: old_count_ssh is not a number: '$old_count_ssh', setting to 0"
            old_count_ssh=0
        fi
    fi

    if ipset list -n 2>/dev/null | grep -q "^$IPSET_NAME_K8S$"; then
        old_count_k8s=$(ipset list $IPSET_NAME_K8S | grep 'Number of entries:' | awk '{print $4}')
        # Ensure it's a number
        if ! [[ "$old_count_k8s" =~ ^[0-9]+$ ]]; then
            echo "Warning: old_count_k8s is not a number: '$old_count_k8s', setting to 0"
            old_count_k8s=0
        fi
    fi

    echo "DEBUG: old_count_api = $old_count_api"
    echo "DEBUG: old_count_ssh = $old_count_ssh"
    echo "DEBUG: old_count_k8s = $old_count_k8s"

    # Create temporary ipsets
    temp_ipset_api="${IPSET_NAME_API}_temp"
    temp_ipset_ssh="${IPSET_NAME_SSH}_temp"
    temp_ipset_k8s="${IPSET_NAME_K8S}_temp"

    # Destroy temp ipsets if they exist
    ipset destroy $temp_ipset_api 2>/dev/null || true
    ipset destroy $temp_ipset_ssh 2>/dev/null || true
    ipset destroy $temp_ipset_k8s 2>/dev/null || true

    # Create new temp ipsets with correct type
    ipset create $temp_ipset_api $IPSET_TYPE
    ipset create $temp_ipset_ssh $IPSET_TYPE
    ipset create $temp_ipset_k8s $IPSET_TYPE

    # Add all networks from API to the API temporary ipset (full access)
    valid_network_count=0
    if [ "$network_count" -gt 0 ]; then
        echo "DEBUG: Processing $network_count networks from API"
        while IFS= read -r network; do
            if [ -z "$network" ]; then
                echo "DEBUG: Skipping empty network"
                continue
            fi

            echo "DEBUG: Validating network: '$network'"
            if validate_ip_network "$network"; then
                echo "DEBUG: Valid network: $network - adding to ipset"
                ipset add $temp_ipset_api $network 2>/dev/null
                add_result=$?
                if [ $add_result -eq 0 ]; then
                    valid_network_count=$((valid_network_count + 1))
                    echo "DEBUG: Successfully added $network to ipset"
                else
                    echo "DEBUG: Failed to add $network to ipset (error code: $add_result)"
                fi
            else
                echo "Invalid network format from API: '$network'"
            fi
        done <<< "$networks"
        echo "DEBUG: Added $valid_network_count valid networks from API"
    fi

    # Add network ranges from allowed-networks-api.conf to K8S ipset (port 6443 only)
    k8s_network_count=0
    if [ -f "$API_NETWORKS_FILE" ]; then
        echo "DEBUG: Processing networks from $API_NETWORKS_FILE"
        while IFS= read -r network || [ -n "$network" ]; do
            # Skip comments and empty lines
            if [[ "$network" =~ ^[[:space:]]*# ]] || [[ -z "$network" ]]; then
                continue
            fi

            # Trim whitespace
            network=$(echo "$network" | xargs)

            echo "DEBUG: Validating network from file: '$network'"
            if validate_ip_network "$network"; then
                echo "DEBUG: Valid network: $network - adding to K8S ipset"
                ipset add $temp_ipset_k8s $network 2>/dev/null
                add_result=$?
                if [ $add_result -eq 0 ]; then
                    k8s_network_count=$((k8s_network_count + 1))
                    echo "DEBUG: Successfully added $network to K8S ipset"
                else
                    echo "DEBUG: Failed to add $network to K8S ipset (error code: $add_result)"
                fi
            else
                echo "Invalid network format in API config file: '$network'"
            fi
        done < "$API_NETWORKS_FILE"

        echo "Added $k8s_network_count network ranges from $API_NETWORKS_FILE to K8S ipset (port $K8S_PORT only)"
    else
        echo "No $API_NETWORKS_FILE file found"
    fi

    # Add network ranges from allowed-networks-ssh.conf if it exists
    ssh_network_count=0
    if [ -f "$SSH_NETWORKS_FILE" ]; then
        echo "DEBUG: Processing networks from $SSH_NETWORKS_FILE"
        while IFS= read -r network || [ -n "$network" ]; do
            # Skip comments and empty lines
            if [[ "$network" =~ ^[[:space:]]*# ]] || [[ -z "$network" ]]; then
                continue
            fi

            # Trim whitespace
            network=$(echo "$network" | xargs)

            echo "DEBUG: Validating network from SSH file: '$network'"
            if validate_ip_network "$network"; then
                echo "DEBUG: Valid network: $network - adding to SSH ipset"
                ipset add $temp_ipset_ssh $network 2>/dev/null
                add_result=$?
                if [ $add_result -eq 0 ]; then
                    ssh_network_count=$((ssh_network_count + 1))
                    echo "DEBUG: Successfully added $network to SSH ipset"
                else
                    echo "DEBUG: Failed to add $network to SSH ipset (error code: $add_result)"
                fi
            else
                echo "Invalid network format in SSH config file: '$network'"
            fi
        done < "$SSH_NETWORKS_FILE"

        echo "Added $ssh_network_count network ranges from $SSH_NETWORKS_FILE"
    else
        echo "No $SSH_NETWORKS_FILE file found"
    fi

    # Update API ipset (full access)
    new_count_api=0
    echo "DEBUG: valid_network_count = $valid_network_count"
    if [ "$valid_network_count" -gt 0 ] || [ -f "$LAST_SUCCESSFUL_IPS_FILE" ]; then
        echo "DEBUG: Updating API ipset with valid networks"
        # Check if main ipset exists with correct type
        if ipset list -n 2>/dev/null | grep -q "^$IPSET_NAME_API$"; then
            current_type=$(ipset list $IPSET_NAME_API | grep "Type:" | awk '{print $2}')
            if [ "$current_type" != "$IPSET_TYPE" ]; then
                echo "API ipset has wrong type ($current_type). Destroying and recreating..."
                # Save entries from temp ipset
                ipset save $temp_ipset_api > /tmp/temp_ipset_api_entries
                # Destroy both ipsets
                ipset destroy $IPSET_NAME_API
                ipset destroy $temp_ipset_api
                # Recreate main ipset with correct type
                ipset create $IPSET_NAME_API $IPSET_TYPE
                # Restore entries to main ipset
                ipset restore < /tmp/temp_ipset_api_entries
                rm /tmp/temp_ipset_api_entries
                echo "API ipset recreated with correct type."
            else
                # Swap the temporary ipset with the main one (atomic operation)
                echo "DEBUG: Swapping temp ipset with main ipset"
                ipset swap $temp_ipset_api $IPSET_NAME_API
                ipset destroy $temp_ipset_api
            fi
        else
            # Main ipset doesn't exist, rename temp to main
            echo "DEBUG: Main ipset doesn't exist, renaming temp to main"
            ipset rename $temp_ipset_api $IPSET_NAME_API
        fi

        # Get new ipset count after swap
        if ipset list -n 2>/dev/null | grep -q "^$IPSET_NAME_API$"; then
            new_count_api=$(ipset list $IPSET_NAME_API | grep 'Number of entries:' | awk '{print $4}')
            # Ensure it's a number
            if ! [[ "$new_count_api" =~ ^[0-9]+$ ]]; then
                echo "Warning: new_count_api is not a number: '$new_count_api', setting to 0"
                new_count_api=0
            fi
        fi

        echo "DEBUG: new_count_api = $new_count_api"

        # Report the current entry count clearly
        echo "Current API networks count (full access): $new_count_api"

        # Report changes if any - using numeric comparison
        if [ "$old_count_api" -ne "$new_count_api" ]; then
            diff=$((new_count_api - old_count_api))
            if [ $diff -gt 0 ]; then
                echo "Added $diff new unique networks to the API firewall (full access)"
            else
                echo "Removed $((diff * -1)) networks from the API firewall (full access)"
            fi
        fi
    else
        # Don't swap if we have no valid entries and no cached data
        ipset destroy $temp_ipset_api 2>/dev/null || true
        echo "WARNING: No valid networks to add to API firewall. Keeping existing rules."
        echo "Current API networks count (full access): $old_count_api"
    fi

    # Update K8S ipset (port 6443 only)
    new_count_k8s=0
    if [ "$k8s_network_count" -gt 0 ]; then
        # Check if main ipset exists with correct type
        if ipset list -n 2>/dev/null | grep -q "^$IPSET_NAME_K8S$"; then
            current_type=$(ipset list $IPSET_NAME_K8S | grep "Type:" | awk '{print $2}')
            if [ "$current_type" != "$IPSET_TYPE" ]; then
                echo "K8S ipset has wrong type ($current_type). Destroying and recreating..."
                # Save entries from temp ipset
                ipset save $temp_ipset_k8s > /tmp/temp_ipset_k8s_entries
                # Destroy both ipsets
                ipset destroy $IPSET_NAME_K8S
                ipset destroy $temp_ipset_k8s
                # Recreate main ipset with correct type
                ipset create $IPSET_NAME_K8S $IPSET_TYPE
                # Restore entries to main ipset
                ipset restore < /tmp/temp_ipset_k8s_entries
                rm /tmp/temp_ipset_k8s_entries
                echo "K8S ipset recreated with correct type."
            else
                # Swap the temporary ipset with the main one (atomic operation)
                ipset swap $temp_ipset_k8s $IPSET_NAME_K8S
                ipset destroy $temp_ipset_k8s
            fi
        else
            # Main ipset doesn't exist, rename temp to main
            ipset rename $temp_ipset_k8s $IPSET_NAME_K8S
        fi

        # Get new ipset count after swap
        if ipset list -n 2>/dev/null | grep -q "^$IPSET_NAME_K8S$"; then
            new_count_k8s=$(ipset list $IPSET_NAME_K8S | grep 'Number of entries:' | awk '{print $4}')
            # Ensure it's a number
            if ! [[ "$new_count_k8s" =~ ^[0-9]+$ ]]; then
                echo "Warning: new_count_k8s is not a number: '$new_count_k8s', setting to 0"
                new_count_k8s=0
            fi
        fi

        echo "DEBUG: new_count_k8s = $new_count_k8s"

        # Report the current entry count clearly
        echo "Current K8S networks count (port $K8S_PORT only): $new_count_k8s"

        # Report changes if any - using numeric comparison
        if [ "$old_count_k8s" -ne "$new_count_k8s" ]; then
            diff=$((new_count_k8s - old_count_k8s))
            if [ $diff -gt 0 ]; then
                echo "Added $diff new unique networks to the K8S firewall (port $K8S_PORT only)"
            else
                echo "Removed $((diff * -1)) networks from the K8S firewall (port $K8S_PORT only)"
            fi
        fi
    else
        # Don't swap if we have no valid entries
        ipset destroy $temp_ipset_k8s 2>/dev/null || true
        echo "WARNING: No valid networks to add to K8S firewall. Keeping existing rules."
        echo "Current K8S networks count (port $K8S_PORT only): $old_count_k8s"
    fi

    # Update SSH ipset
    new_count_ssh=0
    if [ "$ssh_network_count" -gt 0 ]; then
        # Check if main ipset exists with correct type
        if ipset list -n 2>/dev/null | grep -q "^$IPSET_NAME_SSH$"; then
            current_type=$(ipset list $IPSET_NAME_SSH | grep "Type:" | awk '{print $2}')
            if [ "$current_type" != "$IPSET_TYPE" ]; then
                echo "SSH ipset has wrong type ($current_type). Destroying and recreating..."
                # Save entries from temp ipset
                ipset save $temp_ipset_ssh > /tmp/temp_ipset_ssh_entries
                # Destroy both ipsets
                ipset destroy $IPSET_NAME_SSH
                ipset destroy $temp_ipset_ssh
                # Recreate main ipset with correct type
                ipset create $IPSET_NAME_SSH $IPSET_TYPE
                # Restore entries to main ipset
                ipset restore < /tmp/temp_ipset_ssh_entries
                rm /tmp/temp_ipset_ssh_entries
                echo "SSH ipset recreated with correct type."
            else
                # Swap the temporary ipset with the main one (atomic operation)
                ipset swap $temp_ipset_ssh $IPSET_NAME_SSH
                ipset destroy $temp_ipset_ssh
            fi
        else
            # Main ipset doesn't exist, rename temp to main
            ipset rename $temp_ipset_ssh $IPSET_NAME_SSH
        fi

        # Get new ipset count after swap
        if ipset list -n 2>/dev/null | grep -q "^$IPSET_NAME_SSH$"; then
            new_count_ssh=$(ipset list $IPSET_NAME_SSH | grep 'Number of entries:' | awk '{print $4}')
            # Ensure it's a number
            if ! [[ "$new_count_ssh" =~ ^[0-9]+$ ]]; then
                echo "Warning: new_count_ssh is not a number: '$new_count_ssh', setting to 0"
                new_count_ssh=0
            fi
        fi

        echo "DEBUG: new_count_ssh = $new_count_ssh"

        # Report the current entry count clearly
        echo "Current SSH networks count: $new_count_ssh"

        # Report changes if any - using numeric comparison
        if [ "$old_count_ssh" -ne "$new_count_ssh" ]; then
            diff=$((new_count_ssh - old_count_ssh))
            if [ $diff -gt 0 ]; then
                echo "Added $diff new unique networks to the SSH firewall"
            else
                echo "Removed $((diff * -1)) networks from the SSH firewall"
            fi
        fi
    else
        # Don't swap if we have no valid entries
        ipset destroy $temp_ipset_ssh 2>/dev/null || true
        echo "WARNING: No valid networks to add to SSH firewall. Keeping existing rules."
        echo "Current SSH networks count: $old_count_ssh"
    fi

    echo "DEBUG: Current ipset contents after adding networks:"
    ipset list $IPSET_NAME_API
}

# Main loop to poll API and update firewall rules
echo "Starting continuous firewall rule updates..."
while true; do
    # Add timestamp to each iteration
    echo "===== $(date '+%Y-%m-%d %H:%M:%S') ====="
    update_allowed_networks
    echo "-------------------------------------"
    sleep 5
done
