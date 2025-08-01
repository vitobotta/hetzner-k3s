#!/bin/bash

CONFIG_FILE="/etc/systemd/system/ssh.socket.d/listen.conf"

# Check if the configuration file exists
if [[ ! -f "$CONFIG_FILE" ]]; then
    echo "Configuration file $CONFIG_FILE does not exist."
    exit 0
fi

echo "Processing SSH socket configuration: $CONFIG_FILE"

# Create a backup copy in /root
BACKUP_FILE="/root/listen.conf.bak"
if sudo cp "$CONFIG_FILE" "$BACKUP_FILE"; then
    echo "Backup created: $BACKUP_FILE"
else
    echo "Failed to create backup. Aborting."
    exit 1
fi

# Create a temporary file for the modified content
TEMP_FILE=$(mktemp)
LISTEN_STREAM_COUNT=0
BIND_IPV6_ONLY_FOUND=false

# Read the file line by line
while IFS= read -r line; do
    # Skip empty lines and comments for processing
    trimmed_line=$(echo "$line" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

    # Check if this is a ListenStream line
    if [[ "$trimmed_line" =~ ^ListenStream= ]]; then
        LISTEN_STREAM_COUNT=$((LISTEN_STREAM_COUNT + 1))
        echo "$line"
        continue
    fi

    # Check if this is a BindIPv6Only setting (commented or uncommented)
    if [[ "$trimmed_line" =~ ^#?BindIPv6Only= ]]; then
        BIND_IPV6_ONLY_FOUND=true
        # Replace with correct value, uncomment if needed
        echo "BindIPv6Only=default"
        continue
    fi

    # If we've found ListenStream lines and haven't found BindIPv6Only yet,
    # and we're moving to a new section, add the setting after the ListenStream lines
    if [[ "$LISTEN_STREAM_COUNT" -gt 0 && "$BIND_IPV6_ONLY_FOUND" == false && "$trimmed_line" =~ ^\[ && "$trimmed_line" != *ListenStream* ]]; then
        echo "BindIPv6Only=default"
        BIND_IPV6_ONLY_FOUND=true
    fi

    echo "$line"
done < "$CONFIG_FILE" > "$TEMP_FILE"

# If we found ListenStream but no BindIPv6Only, add it at the end
if [[ "$LISTEN_STREAM_COUNT" -gt 0 && "$BIND_IPV6_ONLY_FOUND" == false ]]; then
    echo "BindIPv6Only=default" >> "$TEMP_FILE"
fi

# Replace the original file with the modified one
if sudo mv "$TEMP_FILE" "$CONFIG_FILE"; then
    echo "Configuration updated successfully."

    # Reload systemd and restart the ssh.socket to apply changes
    sudo systemctl daemon-reload
    sudo systemctl restart ssh.socket
    echo "SSH socket reloaded and restarted."
else
    echo "Failed to update configuration file."
    rm -f "$TEMP_FILE"
    exit 1
fi
