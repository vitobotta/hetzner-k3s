#!/bin/bash

CONFIG_FILE="/etc/systemd/system/ssh.socket.d/listen.conf"

# Check if the configuration file exists
if [[ ! -f "$CONFIG_FILE" ]]; then
    echo "Configuration file $CONFIG_FILE does not exist."
    exit 0
fi

echo "Processing SSH socket configuration: $CONFIG_FILE"

# Create a backup copy in /root with timestamp
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
BACKUP_FILE="/root/listen.conf.bak_$TIMESTAMP"
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

# Read the file into an array to preserve all lines exactly as they are
# Handle files without trailing newlines
ALL_LINES=()
while IFS= read -r line || [[ -n "$line" ]]; do
    ALL_LINES+=("$line")
    
    trimmed_line=$(echo "$line" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    
    # Check if this is a ListenStream line
    if [[ "$trimmed_line" =~ ^ListenStream= ]]; then
        LISTEN_STREAM_COUNT=$((LISTEN_STREAM_COUNT + 1))
    fi
    
    # Check if this is a BindIPv6Only setting (commented or uncommented)
    if [[ "$trimmed_line" =~ ^#?BindIPv6Only= ]]; then
        BIND_IPV6_ONLY_FOUND=true
    fi
done < "$CONFIG_FILE"

# Output all lines, handling BindIPv6Only insertion/replacement
BIND_IPV6_ONLY_ADDED=false
LAST_LISTEN_STREAM_INDEX=-1

# Find the index of the last ListenStream line
for i in "${!ALL_LINES[@]}"; do
    line="${ALL_LINES[$i]}"
    trimmed_line=$(echo "$line" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    if [[ "$trimmed_line" =~ ^ListenStream= ]]; then
        LAST_LISTEN_STREAM_INDEX=$i
    fi
done

# Output lines with BindIPv6Only handling
for i in "${!ALL_LINES[@]}"; do
    line="${ALL_LINES[$i]}"
    trimmed_line=$(echo "$line" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    
    # Handle BindIPv6Only lines
    if [[ "$trimmed_line" =~ ^#?BindIPv6Only= ]]; then
        if [[ "$BIND_IPV6_ONLY_ADDED" == false ]]; then
            echo "BindIPv6Only=default"
            BIND_IPV6_ONLY_ADDED=true
        fi
        continue
    fi
    
    # Output the current line
    echo "$line"
    
    # After the last ListenStream line, add BindIPv6Only if needed
    if [[ "$i" -eq "$LAST_LISTEN_STREAM_INDEX" && "$BIND_IPV6_ONLY_FOUND" == false && "$BIND_IPV6_ONLY_ADDED" == false ]]; then
        echo "BindIPv6Only=default"
        BIND_IPV6_ONLY_ADDED=true
    fi
done > "$TEMP_FILE"

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
