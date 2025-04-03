#!/bin/bash

# Token for API authentication
TOKEN="{{ hetzner_token }}"
API_URL="{{ ips_query_server_url }}/ips"
IPSET_NAME="allowed_ips"
NETWORKS_FILE="/root/allowed_networks.conf"
MAX_RETRIES=3
RETRY_DELAY=5
IPSET_TYPE="hash:net"  # Explicitly define the ipset type

# Check if script is run as root
if [ "$(id -u)" -ne 0 ]; then
    echo "This script must be run as root" >&2
    exit 1
fi

# Install required packages without prompting
install_packages() {
    echo "Installing required packages..."
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -qq
    apt-get install -y -qq jq ipset iptables-persistent curl
    echo "Required packages installed."
}

# Check and install required packages
for pkg in jq ipset curl; do
    if ! command -v $pkg &> /dev/null; then
        install_packages
        break
    fi
done

# Check for iptables-persistent
if ! dpkg -l | grep -q iptables-persistent; then
    # Pre-answer the prompt for saving current rules
    echo iptables-persistent iptables-persistent/autosave_v4 boolean true | debconf-set-selections
    echo iptables-persistent iptables-persistent/autosave_v6 boolean true | debconf-set-selections
    apt-get install -y -qq iptables-persistent
fi

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

    # Remove existing ipset if it exists with wrong type
    if ipset list -n | grep -q "^$IPSET_NAME$"; then
        current_type=$(ipset list $IPSET_NAME | grep "Type:" | awk '{print $2}')
        if [ "$current_type" != "$IPSET_TYPE" ]; then
            echo "Existing ipset has wrong type ($current_type). Recreating with correct type ($IPSET_TYPE)..."
            ipset destroy $IPSET_NAME
        fi
    fi

    # Create ipset if it doesn't exist
    if ! ipset list -n | grep -q "^$IPSET_NAME$"; then
        echo "Creating ipset for allowed IPs..."
        ipset create $IPSET_NAME $IPSET_TYPE hashsize 4096
    fi

    # Add ipset rule to iptables if not already present
    if ! iptables -C INPUT -m set --match-set $IPSET_NAME src -j ACCEPT 2>/dev/null; then
        echo "Adding ipset rule to iptables..."
        iptables -A INPUT -m set --match-set $IPSET_NAME src -j ACCEPT
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

# Create a status script for easy checking
create_status_script() {
    cat > /usr/local/bin/firewall-status << EOF
#!/bin/bash

IPSET_NAME="$IPSET_NAME"
NETWORKS_FILE="$NETWORKS_FILE"

echo "===== Firewall Status Check ====="
echo

# Check if UFW is installed and active
if command -v ufw &> /dev/null; then
    ufw_status=\$(ufw status | grep "Status:")
    echo "UFW Status: \$ufw_status"

    if echo "\$ufw_status" | grep -q "active"; then
        echo "WARNING: UFW is active and may conflict with direct iptables rules"
        echo "UFW Rules:"
        ufw status numbered
        echo
    fi
fi

# Check for allowed networks file
echo "===== Allowed Networks File ====="
if [ -f "\$NETWORKS_FILE" ]; then
    network_count=\$(grep -v "^#" "\$NETWORKS_FILE" | grep -v "^$" | wc -l)
    echo "Found allowed_networks.conf with \$network_count network ranges"
    echo "Network ranges:"
    grep -v "^#" "\$NETWORKS_FILE" | grep -v "^$" | head -10

    if [ "\$network_count" -gt 10 ]; then
        echo "... and \$((\$network_count - 10)) more networks"
    fi
else
    echo "No allowed_networks.conf file found in \$HOME"
fi
echo

# Check ipset status
echo "===== IPSET Status ====="
if command -v ipset &> /dev/null; then
    if ipset list -n | grep -q "\$IPSET_NAME"; then
        ip_count=\$(ipset list \$IPSET_NAME | grep "Number of entries:" | awk '{print \$4}')
        ipset_type=\$(ipset list \$IPSET_NAME | grep "Type:" | awk '{print \$2}')
        echo "IP Allowlist Status: Active with \$ip_count entries (Type: \$ipset_type)"
        echo "First 10 allowed entries (sample):"
        ipset list \$IPSET_NAME | grep -A 10 "Members:" | tail -10

        if [ "\$ip_count" -gt 10 ]; then
            echo "... and \$((\$ip_count - 10)) more entries"
        fi
    else
        echo "IP Allowlist Status: Not found (ipset '\$IPSET_NAME' doesn't exist)"
    fi
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

    # Check for our ipset rule
    echo "Checking for ipset rule:"
    if iptables -L INPUT -v | grep -q "match-set \$IPSET_NAME"; then
        echo "✓ FOUND: ipset rule is active"
        iptables -L INPUT -v | grep "match-set \$IPSET_NAME"
    else
        echo "✗ NOT FOUND: ipset rule is missing from iptables"
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
    service_status=\$(systemctl is-active firewall-updater.service)
    echo "Service Status: \$service_status"

    if [ "\$service_status" = "active" ]; then
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
EOF

    chmod +x /usr/local/bin/firewall-status
    echo "Created firewall status script at /usr/local/bin/firewall-status"
    echo "You can run 'sudo firewall-status' anytime to check your firewall configuration"
}

# Create the service script that will run continuously
create_service_script() {
    # Create a dedicated service script
    cat > /usr/local/bin/firewall-updater << EOF
#!/bin/bash

# Token for API authentication
TOKEN="$TOKEN"
API_URL="$API_URL"
IPSET_NAME="$IPSET_NAME"
NETWORKS_FILE="$NETWORKS_FILE"
MAX_RETRIES=$MAX_RETRIES
RETRY_DELAY=$RETRY_DELAY
IPSET_TYPE="$IPSET_TYPE"
LAST_SUCCESSFUL_IPS_FILE="/tmp/last_successful_ips.json"

# Function to validate IP/network format
validate_ip_network() {
    local ip_net=\$1

    # Check if it's a valid IP or network range
    if [[ \$ip_net =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+(/[0-9]+)?$ ]]; then
        return 0
    else
        return 1
    fi
}

# Function to fetch IPs from API with retry logic
fetch_ips_from_api() {
    local retry_count=0
    local max_retries=\$MAX_RETRIES
    local delay=\$RETRY_DELAY
    local response=""

    while [ \$retry_count -lt \$max_retries ]; do
        # Attempt to fetch IPs with timeout
        response=\$(curl -s -m 10 -H "Hetzner-Token: \$TOKEN" "\$API_URL")

        # Check if response is valid JSON with IPs
        if echo "\$response" | jq -e . >/dev/null 2>&1 && [ "\$(echo "\$response" | jq 'length')" -gt 0 ]; then
            # Success - save the response and return it
            echo "\$response" > "\$LAST_SUCCESSFUL_IPS_FILE"
            echo "\$response"
            return 0
        fi

        # Increment retry counter
        retry_count=\$((retry_count + 1))

        if [ \$retry_count -lt \$max_retries ]; then
            echo "API request failed (attempt \$retry_count/\$max_retries). Retrying in \$delay seconds..."
            sleep \$delay
        else
            echo "API request failed after \$max_retries attempts."
        fi
    done

    # All retries failed, return empty response
    echo ""
    return 1
}

# Function to update allowed IPs in ipset
update_allowed_ips() {
    # Get IPs from API with retry logic
    response=\$(fetch_ips_from_api)
    api_success=\$?

    # If API request failed, try to use cached IPs
    if [ \$api_success -ne 0 ]; then
        if [ -f "\$LAST_SUCCESSFUL_IPS_FILE" ]; then
            echo "Using cached IPs from last successful request"
            response=\$(cat "\$LAST_SUCCESSFUL_IPS_FILE")

            # Check if cached response is valid
            if ! echo "\$response" | jq -e . >/dev/null 2>&1; then
                echo "Error: Cached response is invalid. Continuing with only network ranges."
                response='[]'
            fi
        else
            echo "No cached IPs available. Continuing with only network ranges."
            response='[]'
        fi
    fi

    # Extract IPs from JSON array
    ips=\$(echo "\$response" | jq -r '.[]')

    # Count the number of IPs received
    if [ -z "\$ips" ]; then
        ip_count=0
        echo "Using 0 IPs from API"
    else
        ip_count=\$(echo "\$ips" | wc -l)
        echo "Using \$ip_count IPs from API"
    fi

    # Get current ipset count before update
    if ipset list -n | grep -q "^\$IPSET_NAME\$"; then
        old_count=\$(ipset list \$IPSET_NAME | grep "Number of entries:" | awk '{print \$4}')
    else
        old_count=0
    fi

    # Create a temporary ipset with the same type as the main one
    temp_ipset="\${IPSET_NAME}_temp"

    # Destroy temp ipset if it exists
    ipset destroy \$temp_ipset 2>/dev/null || true

    # Create new temp ipset with correct type
    ipset create \$temp_ipset \$IPSET_TYPE hashsize 4096

    # Add all IPs from API to the temporary ipset
    valid_ip_count=0
    if [ "\$ip_count" -gt 0 ]; then
        for ip in \$ips; do
            if validate_ip_network "\$ip"; then
                ipset add \$temp_ipset \$ip 2>/dev/null || true
                valid_ip_count=\$((valid_ip_count + 1))
            else
                echo "Invalid IP format from API: \$ip"
            fi
        done
    fi

    # Add network ranges from allowed_networks.conf if it exists
    if [ -f "\$NETWORKS_FILE" ]; then
        network_count=0
        while IFS= read -r network || [ -n "\$network" ]; do
            # Skip comments and empty lines
            if [[ "\$network" =~ ^[[:space:]]*# ]] || [[ -z "\$network" ]]; then
                continue
            fi

            # Trim whitespace
            network=\$(echo "\$network" | xargs)

            if validate_ip_network "\$network"; then
                ipset add \$temp_ipset \$network 2>/dev/null || true
                network_count=\$((network_count + 1))
            else
                echo "Invalid network format in config file: \$network"
            fi
        done < "\$NETWORKS_FILE"

        echo "Added \$network_count network ranges from allowed_networks.conf"
    else
        echo "No allowed_networks.conf file found"
    fi

    # Only swap if we have at least one valid entry or if we're using cached data
    if [ "\$valid_ip_count" -gt 0 ] || [ "\$network_count" -gt 0 ] || [ -f "\$LAST_SUCCESSFUL_IPS_FILE" ]; then
        # Check if main ipset exists with correct type
        if ipset list -n | grep -q "^\$IPSET_NAME\$"; then
            current_type=\$(ipset list \$IPSET_NAME | grep "Type:" | awk '{print \$2}')
            if [ "\$current_type" != "\$IPSET_TYPE" ]; then
                echo "Main ipset has wrong type (\$current_type). Destroying and recreating..."
                # Save entries from temp ipset
                ipset save \$temp_ipset > /tmp/temp_ipset_entries
                # Destroy both ipsets
                ipset destroy \$IPSET_NAME
                ipset destroy \$temp_ipset
                # Recreate main ipset with correct type
                ipset create \$IPSET_NAME \$IPSET_TYPE hashsize 4096
                # Restore entries to main ipset
                ipset restore < /tmp/temp_ipset_entries
                rm /tmp/temp_ipset_entries
                echo "Main ipset recreated with correct type."
            else
                # Swap the temporary ipset with the main one (atomic operation)
                ipset swap \$temp_ipset \$IPSET_NAME
                ipset destroy \$temp_ipset
            fi
        else
            # Main ipset doesn't exist, rename temp to main
            ipset rename \$temp_ipset \$IPSET_NAME
        fi

        # Get new ipset count after swap
        new_count=\$(ipset list \$IPSET_NAME | grep "Number of entries:" | awk '{print \$4}')

        # Report the current entry count clearly
        echo "Current entry count: \$new_count"

        # Report changes if any
        if [ "\$old_count" != "\$new_count" ]; then
            diff=\$((new_count - old_count))
            if [ \$diff -gt 0 ]; then
                echo "Added \$diff new unique entries to the firewall"
            else
                echo "Removed \$((diff * -1)) entries from the firewall"
            fi
        fi
    else
        # Don't swap if we have no valid entries and no cached data
        ipset destroy \$temp_ipset
        echo "WARNING: No valid entries to add to firewall. Keeping existing rules."
        echo "Current entry count: \$old_count"
    fi
}

# Main loop to poll API and update firewall rules
echo "Starting continuous firewall rule updates..."
while true; do
    # Add timestamp to each iteration
    echo "===== \$(date '+%Y-%m-%d %H:%M:%S') ====="
    update_allowed_ips
    echo "-------------------------------------"
    sleep 5
done
EOF

    chmod +x /usr/local/bin/firewall-updater
    echo "Created firewall updater script at /usr/local/bin/firewall-updater"
}

# Setup systemd service
setup_systemd_service() {
    # Create a systemd service for the updater
    cat > /etc/systemd/system/firewall-updater.service << EOF
[Unit]
Description=Firewall IP Updater Service
After=network.target

[Service]
Type=simple
ExecStart=/usr/local/bin/firewall-updater
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

    # Create a script to restore the ipset and iptables rule on boot
    cat > /etc/network/if-pre-up.d/ipset-restore << EOF
#!/bin/bash
ipset create $IPSET_NAME $IPSET_TYPE hashsize 4096 2>/dev/null || true
iptables -C INPUT -m set --match-set $IPSET_NAME src -j ACCEPT 2>/dev/null || iptables -A INPUT -m set --match-set $IPSET_NAME src -j ACCEPT
exit 0
EOF
    chmod +x /etc/network/if-pre-up.d/ipset-restore

    # Reload systemd, enable and start the service
    systemctl daemon-reload
    systemctl enable firewall-updater.service
    systemctl start firewall-updater.service

    echo "Firewall updater service has been enabled and started"
    echo "Service status:"
    systemctl status firewall-updater.service --no-pager
}

# Main execution
echo "Setting up scalable IP-based firewall..."

# Handle UFW automatically
handle_ufw

# Setup iptables rules
setup_iptables

# Create the service script
create_service_script

# Create status script
create_status_script

# Setup and start the systemd service
setup_systemd_service

echo
echo "Setup complete! The firewall-updater service is now running."
echo "You can check its status with: sudo systemctl status firewall-updater.service"
echo "You can check the firewall configuration with: sudo firewall-status"
echo
echo "To add custom network ranges, create a file at: $NETWORKS_FILE"
echo "Add one network range per line (e.g., 192.168.1.0/24)"
echo "The service will automatically include these ranges in the firewall."
echo
