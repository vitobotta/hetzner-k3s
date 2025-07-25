#!/bin/bash

fn_cloud="/var/lib/cloud/instance/boot-finished"

function await_cloud_init() {
  echo "🕒 Awaiting cloud config (may take a minute...)"

  # Wait for up to 5 minutes (300 seconds)
  MAX_WAIT=300
  COUNT=0

  while [ $COUNT -lt $MAX_WAIT ]; do
    if [ -f "$fn_cloud" ]; then
      echo "Cloud init finished: $(cat "$fn_cloud")"
      return 0
    fi

    sleep 1
    COUNT=$((COUNT + 1))

    # Print a dot every 10 seconds to show we're still waiting
    if [ $((COUNT % 10)) -eq 0 ]; then
      echo -n "."
    fi
  done

  echo ""
  echo "ERROR: Timeout waiting for cloud-init to finish"
  return 1
}

# Check if cloud-init has already finished
if [ -f "$fn_cloud" ]; then
  echo "Cloud init already finished: $(cat "$fn_cloud")"
else
  await_cloud_init
fi