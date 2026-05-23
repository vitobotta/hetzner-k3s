touch /etc/initialized

HOSTNAME=$(hostname -f)
PUBLIC_IP=$(hostname -I | awk '{print $1}')

IPV4_ENABLED="{{ ipv4_enabled }}"

# Network configuration
if [ "{{ private_network_enabled }}" = "true" ]; then
  echo "Using Hetzner private network" >/var/log/hetzner-k3s.log
  SUBNET="{{ private_network_subnet }}"

  # Wait for private network interface to be available
  MAX_ATTEMPTS=30
  DELAY=10

  for i in $(seq 1 $MAX_ATTEMPTS); do
    # Simplified network interface detection
    NETWORK_INTERFACE=$(
      ip -o link show |
        awk -F': ' '/mtu (1450|1280)/ {print $2}' |
        grep -Ev 'cilium|lxc|br|flannel|docker|veth' |
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

# Get instance ID for public network
KUBELET_INSTANCE_ID=""
if [ "{{ private_network_enabled }}" = "false" ]; then
  INSTANCE_ID=$(curl -s http://169.254.169.254/hetzner/v1/metadata/instance-id)
  if [ -n "$INSTANCE_ID" ]; then
    KUBELET_INSTANCE_ID="--kubelet-arg=provider-id=hcloud://$INSTANCE_ID"
  else
    echo "WARNING: Could not retrieve instance ID" 2>&1 | tee -a /var/log/hetzner-k3s.log
  fi
fi

# DNS configuration for /etc/k8s-resolv.conf (used by kubelet --resolv-conf)
# On IPv6-only nodes, 8.8.8.8 is unreachable. CoreDNS runs in the flannel pod
# network (IPv4-only) and cannot reach IPv6 DNS servers directly. We solve this
# by making systemd-resolved listen on the node's private IP, so both CoreDNS
# (from the pod network) and host-network pods can forward DNS through it.
# systemd-resolved then uses the host's IPv6 upstream DNS servers.
if [ "$IPV4_ENABLED" = "false" ]; then
  echo "IPv6-only node: configuring systemd-resolved DNS proxy on $PRIVATE_IP" 2>&1 | tee -a /var/log/hetzner-k3s.log
  mkdir -p /etc/systemd/resolved.conf.d
  cat > /etc/systemd/resolved.conf.d/k8s-dns-proxy.conf <<DNSEOF
[Resolve]
DNSStubListenerExtra=$PRIVATE_IP
DNSEOF
  systemctl restart systemd-resolved
  echo "nameserver $PRIVATE_IP" > /etc/k8s-resolv.conf
  echo "DNS proxy configured: pods will use $PRIVATE_IP:53 -> systemd-resolved -> IPv6 upstream" 2>&1 | tee -a /var/log/hetzner-k3s.log

  # Install clatd (464XLAT) to provide outbound IPv4 connectivity on IPv6-only nodes.
  # Without this, pods using flannel's IPv4 network (10.244.0.0/16) cannot reach
  # IPv4-only services (e.g. github.com) because the node has no IPv4 internet route.
  # clatd creates a clat interface that translates IPv4 packets into IPv6 via
  # Hetzner's NAT64 gateway, which then translates them back to IPv4.
  # The PLAT prefix is auto-detected via RFC 7050 (ipv4only.arpa DNS64 discovery).
  # This also provides the IPv4 default route that ClusterIP DNAT requires.
  echo "IPv6-only node: installing clatd (464XLAT) for outbound IPv4 connectivity" 2>&1 | tee -a /var/log/hetzner-k3s.log
  DEBIAN_FRONTEND=noninteractive apt-get install -y make tayga perl libnet-ip-perl libnet-dns-perl libjson-perl 2>&1 | tee -a /var/log/hetzner-k3s.log
  curl -fsSL https://github.com/toreanderson/clatd/archive/refs/tags/v2.1.0.tar.gz | tar -xz -C /tmp 2>&1 | tee -a /var/log/hetzner-k3s.log
  make -C /tmp/clatd-2.1.0 install 2>&1 | tee -a /var/log/hetzner-k3s.log
  rm -rf /tmp/clatd-2.1.0
  cat > /etc/clatd.conf <<CLATEOF
v4-conncheck-enable=no
v4-defaultroute-replace=yes
CLATEOF
  systemctl enable --now clatd 2>&1 | tee -a /var/log/hetzner-k3s.log
  echo "clatd installed and started — IPv4 default route via clat0 (NAT64)" 2>&1 | tee -a /var/log/hetzner-k3s.log
else
  echo "nameserver 8.8.8.8" > /etc/k8s-resolv.conf
fi

# Install k3s worker
echo "Installing k3s worker..." 2>&1 | tee -a /var/log/hetzner-k3s.log

curl -sfL https://get.k3s.io | \
  K3S_TOKEN="{{ k3s_token }}" \
  INSTALL_K3S_VERSION="{{ k3s_version }}" \
  K3S_URL=https://{{ api_server_ip_address }}:6443 \
  INSTALL_K3S_EXEC="agent" \
  sh -s - \
    --node-name=$HOSTNAME \
    {{ extra_args }} {{ labels_and_taints }} \
    --node-ip=$PRIVATE_IP \
    --node-external-ip=$PUBLIC_IP \
    $KUBELET_INSTANCE_ID \
    $FLANNEL_SETTINGS 2>&1 | tee -a /var/log/hetzner-k3s.log

# Check if installation was successful
if [ ${PIPESTATUS[0]} -ne 0 ]; then
  echo "ERROR: k3s worker installation failed" 2>&1 | tee -a /var/log/hetzner-k3s.log
  exit 1
fi

echo "k3s worker installation completed successfully" 2>&1 | tee -a /var/log/hetzner-k3s.log

{% if additional_post_k3s_commands != "" %}
# Additional post-k3s commands
{{ additional_post_k3s_commands }}
{% endif %}

echo true >/etc/initialized