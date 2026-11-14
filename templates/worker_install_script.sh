#!/bin/bash
touch /etc/initialized

HOSTNAME=$(hostname -f)
EXTERNAL_NODE_NAME="{{ external_node_name }}"
if [ -n "$EXTERNAL_NODE_NAME" ]; then
  HOSTNAME="$EXTERNAL_NODE_NAME"
fi
PUBLIC_IP=$(hostname -I | awk '{print $1}')
NODE_EXTERNAL_IP="--node-external-ip=$PUBLIC_IP"

# Network configuration
if [ "{{ is_external }}" = "true" ] && [ "{{ private_network_enabled }}" = "true" ] && [ "{{ private_network_external_routing }}" = "true" ]; then
  echo "Using externally routed private network" >/var/log/hetzner-k3s.log
  PRIVATE_IP="{{ external_node_ip }}"
  PUBLIC_IP="{{ external_node_host }}"
  NODE_EXTERNAL_IP=""
  if [ "$PUBLIC_IP" != "$PRIVATE_IP" ]; then
    NODE_EXTERNAL_IP="--node-external-ip=$PUBLIC_IP"
  fi

  # The routed address must belong to this node, not to a NAT gateway or proxy.
  # Select its interface explicitly, including on multihomed/VPN-connected hosts.
  NETWORK_INTERFACE=$(
    ip -4 -o addr show |
      awk -v address="$PRIVATE_IP" 'split($4, cidr, "/") && cidr[1] == address {sub(/@.*/, "", $2); print $2; exit}'
  )
  if [ -z "$NETWORK_INTERFACE" ]; then
    echo "ERROR: Routed cluster IP $PRIVATE_IP is not assigned to a local interface; set external.nodes[].ip to the node's routed IPv4 address" 2>&1 | tee -a /var/log/hetzner-k3s.log
    exit 1
  fi

  FLANNEL_SETTINGS=""
  if [ "{{ cni }}" = "true" ] && [ "{{ cni_mode }}" = "flannel" ]; then
    FLANNEL_SETTINGS="--flannel-iface=$NETWORK_INTERFACE"
  fi
elif [ "{{ private_network_enabled }}" = "true" ]; then
  echo "Using Hetzner private network" >/var/log/hetzner-k3s.log
  SUBNET="{{ private_network_subnet }}"

  # Wait for private network interface to be available
  MAX_ATTEMPTS=30
  DELAY=10

  for i in $(seq 1 $MAX_ATTEMPTS); do
    # Simplified network interface detection.
    # NOTE: MTU 1280 matches WireGuard's default — mesh agents like NetBird,
    # Tailscale, or raw wg-quick create interfaces (wt0, wg0, tailscale0,
    # netbird0, ...) that would otherwise be picked here over the real
    # Hetzner private vlan (enp7s0, MTU 1450). Exclude them by name.
    NETWORK_INTERFACE=$(
      ip -o link show |
        awk -F': ' '/mtu (1450|1280)/ {print $2}' |
        grep -Ev 'cilium|lxc|br|flannel|docker|veth|wt|wg|tailscale|netbird' |
        head -n1
    )

    if [ -n "$NETWORK_INTERFACE" ]; then
      echo "Private network interface $NETWORK_INTERFACE found" 2>&1 | tee -a /var/log/hetzner-k3s.log
      break
    fi

    echo "Waiting for private network interface in subnet $SUBNET... (Attempt $i/$MAX_ATTEMPTS)" 2>&1 | tee -a /var/log/hetzner-k3s.log
    sleep $DELAY
  done

  # Check if we found the interface
  if [ -z "$NETWORK_INTERFACE" ]; then
    echo "ERROR: Timeout waiting for private network interface in subnet $SUBNET" 2>&1 | tee -a /var/log/hetzner-k3s.log
    exit 1
  fi

  # Get private IP address
  PRIVATE_IP=$(
    ip -4 -o addr show dev "$NETWORK_INTERFACE" |
      awk '{print $4}' |
      cut -d'/' -f1 |
      head -n1
  )

  # Verify we got a private IP
  if [ -z "$PRIVATE_IP" ]; then
    echo "ERROR: Could not determine private IP address for interface $NETWORK_INTERFACE" 2>&1 | tee -a /var/log/hetzner-k3s.log
    exit 1
  fi

  echo "Private network IP: $PRIVATE_IP" 2>&1 | tee -a /var/log/hetzner-k3s.log
  FLANNEL_SETTINGS="--flannel-iface=$NETWORK_INTERFACE"
else
  echo "Using public network" >/var/log/hetzner-k3s.log
  PRIVATE_IP="${PUBLIC_IP}"
  FLANNEL_SETTINGS=""
fi

# Create k3s directories
mkdir -p /etc/rancher/k3s

# Create registries.yaml
cat >/etc/rancher/k3s/registries.yaml <<\EOF
{{ private_registry_config | trim }}
EOF

# Set provider ID. Generic external nodes use a non-HCCM scheme; Robot nodes
# use hrobot:// so HCCM can initialize them when Robot support is enabled.
KUBELET_PROVIDER_ID=""
if [ -n "{{ kubelet_provider_id }}" ]; then
  KUBELET_PROVIDER_ID="--kubelet-arg=provider-id={{ kubelet_provider_id }}"
elif [ "{{ private_network_enabled }}" = "false" ]; then
  INSTANCE_ID=$(curl -s --max-time 2 http://169.254.169.254/hetzner/v1/metadata/instance-id 2>/dev/null || true)
  if [ -n "$INSTANCE_ID" ]; then
    KUBELET_PROVIDER_ID="--kubelet-arg=provider-id=hcloud://$INSTANCE_ID"
  else
    echo "WARNING: Could not retrieve instance ID" 2>&1 | tee -a /var/log/hetzner-k3s.log
  fi
fi

# Install k3s worker
echo "Installing k3s worker..." 2>&1 | tee -a /var/log/hetzner-k3s.log

# Sampled before the installer: on a re-run of create the agent of an existing worker is already
# running, and install.sh downloads and verifies the binary before it touches systemd, so an
# installer failure there (a missing release artifact, a network error) leaves that agent running.
# The recovery below must not read that as a successful restart.
agent_state_before_install=$(systemctl is-active k3s-agent 2>/dev/null)

curl -sfL https://get.k3s.io | \
  K3S_TOKEN="{{ k3s_token }}" \
  INSTALL_K3S_VERSION="{{ k3s_version }}" \
  K3S_URL=https://{{ api_server_ip_address }}:6443 \
  INSTALL_K3S_EXEC="agent" \
  sh -s - \
    --node-name=$HOSTNAME \
    {{ extra_args }} {{ labels_and_taints }} \
    --node-ip=$PRIVATE_IP \
    $NODE_EXTERNAL_IP \
    $KUBELET_PROVIDER_ID \
    $FLANNEL_SETTINGS 2>&1 | tee -a /var/log/hetzner-k3s.log
install_status=("${PIPESTATUS[@]}")

# The installer skips the service start when the unit it wrote is identical to the existing one
# ("No change detected so skipping service start"), so an in-place reinstall with unchanged flags
# (k3s-killall.sh, then create) ends with a stopped agent and create times out waiting for the
# node. An inactive or failed unit is started here; one that systemd is already starting is left
# to it.
if [ "${install_status[0]}" -eq 0 ] && [ "${install_status[1]}" -eq 0 ]; then
  agent_state=$(systemctl is-active k3s-agent 2>/dev/null)
  if [ "$agent_state" = "inactive" ] || [ "$agent_state" = "failed" ]; then
    echo "k3s-agent is not running after the installer (unit unchanged, service start skipped): starting it" 2>&1 | tee -a /var/log/hetzner-k3s.log
    systemctl start k3s-agent 2>&1 | tee -a /var/log/hetzner-k3s.log
    install_status=("${PIPESTATUS[0]}" 0)
  fi
fi

# The installer's final "systemctl restart k3s-agent" can report a failure for a start that k3s
# itself gave up on: the agent registers the node and flannel annotates it a moment later, and
# when the node is not yet visible to k3s's own client it shuts down ("flannel failed to sync
# address annotations: node not found"). systemd records the start as failed (Result=protocol)
# and restarts the unit 5 s later, which succeeds. Give the unit that chance before declaring
# the installation failed: only for an agent that was not running before the installer, and only
# while systemd is (re)starting it. A unit whose restart is pending reports "activating"; an
# inactive or failed one is not coming back on its own, so that failure is reported at once.
if { [ "${install_status[0]}" -ne 0 ] || [ "${install_status[1]}" -ne 0 ]; } && [ "$agent_state_before_install" != "active" ]; then
  for i in $(seq 1 24); do
    agent_state=$(systemctl is-active k3s-agent 2>/dev/null)
    if [ "$agent_state" = "active" ]; then
      echo "k3s-agent is active after a failed first start (systemd restarted it); continuing" 2>&1 | tee -a /var/log/hetzner-k3s.log
      install_status=(0 0)
      break
    fi
    [ "$agent_state" = "activating" ] || break
    sleep 5
  done
fi

# Check if installation was successful
if [ "${install_status[0]}" -ne 0 ] || [ "${install_status[1]}" -ne 0 ]; then
  echo "ERROR: k3s worker installation failed" 2>&1 | tee -a /var/log/hetzner-k3s.log
  journalctl -u k3s-agent --no-pager -n 30 2>/dev/null | tee -a /var/log/hetzner-k3s.log || true
  exit 1
fi

echo "k3s worker installation completed successfully" 2>&1 | tee -a /var/log/hetzner-k3s.log

{% if additional_post_k3s_commands != "" %}
# Additional post-k3s commands
{{ additional_post_k3s_commands }}
{% endif %}

echo true >/etc/initialized
