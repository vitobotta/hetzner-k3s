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
else
  echo "Using public network" >/var/log/hetzner-k3s.log
  PRIVATE_IP="${PUBLIC_IP}"
  NETWORK_INTERFACE=""
fi

# Flannel settings
if [ "{{ cni }}" = "true" ] && [ "{{ cni_mode }}" = "flannel" ] && [ "{{ private_network_enabled }}" = "true" ] && [ -n "$NETWORK_INTERFACE" ]; then
  FLANNEL_SETTINGS="{{ flannel_backend }} --flannel-iface=$NETWORK_INTERFACE"
else
  FLANNEL_SETTINGS="{{ flannel_backend }}"
fi

# Embedded registry mirror
if [ "{{ embedded_registry_mirror_enabled }}" = "true" ]; then
  EMBEDDED_REGISTRY_MIRROR="--embedded-registry"
else
  EMBEDDED_REGISTRY_MIRROR=""
fi

# Local path storage class
if [ "{{ local_path_storage_class_enabled }}" = "true" ]; then
  LOCAL_PATH_STORAGE_CLASS=""
else
  LOCAL_PATH_STORAGE_CLASS="--disable local-storage"
fi

# Traefik ingress controller
if [ "{{ traefik_enabled }}" = "true" ]; then
  TRAEFIK_PLUGIN=""
else
  TRAEFIK_PLUGIN="--disable traefik"
fi

# ServiceLB load balancer
if [ "{{ servicelb_enabled }}" = "true" ]; then
  SERVICELB_PLUGIN=""
else
  SERVICELB_PLUGIN="--disable servicelb"
fi

# Metrics Server
if [ "{{ metrics_server_enabled }}" = "true" ]; then
  METRICS_SERVER_PLUGIN=""
else
  METRICS_SERVER_PLUGIN="--disable metrics-server"
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

  # Add IPv4 default route so ClusterIP DNAT works on IPv6-only nodes.
  # IPv6-only Hetzner nodes have no IPv4 default route. Without one, the kernel
  # returns ENETUNREACH immediately for any IPv4 destination (including ClusterIPs
  # like 10.43.0.0/16). Packets never reach nftables, so kube-proxy DNAT rules
  # in the OUTPUT chain cannot rewrite them to local pod endpoints.
  # Hetzner's gateway 172.31.1.1 is always present but doesn't forward IPv4
  # internet traffic — adding it as default just prevents ENETUNREACH so that
  # nftables can process the packets.
  if ! ip route show default 2>/dev/null | grep -q 'default'; then
    # Detect the public-facing interface (eth0 on Intel, enp1s0 on ARM, etc.)
    PUBLIC_IFACE=$(ip -4 -o addr show | grep "$PUBLIC_IP" | awk '{print $2}' | head -1)
    if [ -z "$PUBLIC_IFACE" ]; then
      PUBLIC_IFACE=$(ip route show 172.31.1.1 2>/dev/null | awk '{print $3}' | head -1)
    fi
    if [ -n "$PUBLIC_IFACE" ]; then
      ip route add default via 172.31.1.1 dev "$PUBLIC_IFACE" src "$PUBLIC_IP" metric 500 || true
      echo "Added IPv4 default route via 172.31.1.1 dev $PUBLIC_IFACE for ClusterIP DNAT" 2>&1 | tee -a /var/log/hetzner-k3s.log
    else
      echo "WARNING: Could not detect public interface for IPv4 default route" 2>&1 | tee -a /var/log/hetzner-k3s.log
    fi
  else
    echo "IPv4 default route already exists, skipping" 2>&1 | tee -a /var/log/hetzner-k3s.log
  fi
else
  echo "nameserver 8.8.8.8" > /etc/k8s-resolv.conf
fi

# Install k3s
echo "Installing k3s..." 2>&1 | tee -a /var/log/hetzner-k3s.log

curl -sfL https://get.k3s.io | \
  INSTALL_K3S_VERSION="{{ k3s_version }}" \
  K3S_TOKEN="{{ k3s_token }}" \
  {{ datastore_endpoint }} \
  INSTALL_K3S_SKIP_START=false \
  INSTALL_K3S_EXEC="server" \
  sh -s - \
    --disable-cloud-controller \
    $TRAEFIK_PLUGIN \
    $SERVICELB_PLUGIN \
    $METRICS_SERVER_PLUGIN \
    --write-kubeconfig-mode=644 \
    --node-name=$HOSTNAME \
    --cluster-cidr={{ cluster_cidr }} \
    --service-cidr={{ service_cidr }} \
    --cluster-dns={{ cluster_dns }} \
    --kube-controller-manager-arg="bind-address=0.0.0.0" \
    --kube-proxy-arg="metrics-bind-address=0.0.0.0" \
    --kube-scheduler-arg="bind-address=0.0.0.0" \
    {{ master_taint }} {{ labels_and_taints }} {{ extra_args }} {{ etcd_arguments }} \
    $KUBELET_INSTANCE_ID \
    $FLANNEL_SETTINGS \
    $EMBEDDED_REGISTRY_MIRROR \
    $LOCAL_PATH_STORAGE_CLASS \
    --advertise-address=$PRIVATE_IP \
    --node-ip=$PRIVATE_IP \
    --node-external-ip=$PUBLIC_IP \
    {{ server }} {{ tls_sans }} 2>&1 | tee -a /var/log/hetzner-k3s.log

# Check if installation was successful
if [ ${PIPESTATUS[0]} -ne 0 ]; then
  echo "ERROR: k3s installation failed" 2>&1 | tee -a /var/log/hetzner-k3s.log
  exit 1
fi

echo "k3s installation completed successfully" 2>&1 | tee -a /var/log/hetzner-k3s.log

{% if additional_post_k3s_commands != "" %}
# Additional post-k3s commands
{{ additional_post_k3s_commands }}
{% endif %}

echo true >/etc/initialized