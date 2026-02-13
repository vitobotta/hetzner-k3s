touch /etc/initialized

HOSTNAME=$(hostname -f)
PUBLIC_IP=$(hostname -I | awk '{print $1}')

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
cat >/etc/rancher/k3s/registries.yaml <<EOF
mirrors:
  "*":
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
