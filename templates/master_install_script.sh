#!/bin/bash
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

# CoreDNS: disabled here when hetzner-k3s deploys its own copy, so the packaged manifest and its
# AddOn prune do not fight the managed deployment.
if [ "{{ coredns_enabled }}" = "true" ]; then
  COREDNS_PLUGIN="--disable coredns"
else
  COREDNS_PLUGIN=""
fi

# Kube-proxy arguments
if [ "{{ kube_proxy_enabled }}" = "true" ]; then
  KUBE_PROXY_ARG='--kube-proxy-arg=metrics-bind-address=0.0.0.0'
else
  KUBE_PROXY_ARG=""
fi

# Create k3s directories
mkdir -p /etc/rancher/k3s{% if gvisor_enabled == "true" %}

# gVisor (runsc) is an opt-in extra containerd runtime. apt-get is the only supported path, so a
# node without it stops here instead of later, when a pod first asks for the runtime.
GVISOR_VERSION="{{ gvisor_version }}"

if ! command -v apt-get >/dev/null 2>&1; then
  echo "ERROR: addons.gvisor needs a Debian or Ubuntu image and this node has no apt-get" 2>&1 | tee -a /var/log/hetzner-k3s.log
  exit 1
fi

echo "Installing gVisor (runsc $GVISOR_VERSION)..." 2>&1 | tee -a /var/log/hetzner-k3s.log

apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y apt-transport-https ca-certificates curl gnupg
curl --proto '=https' --proto-redir '=https' -fsSL https://gvisor.dev/archive.key | gpg --batch --yes --dearmor -o /usr/share/keyrings/gvisor-archive-keyring.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/gvisor-archive-keyring.gpg] https://storage.googleapis.com/gvisor/releases release main" | tee /etc/apt/sources.list.d/gvisor.list > /dev/null
apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y "runsc=$GVISOR_VERSION"

if ! command -v runsc >/dev/null 2>&1; then
  echo "ERROR: gVisor (runsc $GVISOR_VERSION) could not be installed" 2>&1 | tee -a /var/log/hetzner-k3s.log
  exit 1
fi

# k3s renders config.toml from this template at every start, so a change needs a restart. The
# content is compared first, the same way the worker script treats registries.yaml, so a re-run of
# create on a node that already has the runtime does not touch systemd.
CONTAINERD_TEMPLATE=/var/lib/rancher/k3s/agent/etc/containerd/config.toml.tmpl
mkdir -p "$(dirname "$CONTAINERD_TEMPLATE")"
containerd_temp=$(mktemp)
cat >"$containerd_temp" <<\GVCONF
{{ "{{ template \"base\" . }}" }}

[plugins."io.containerd.grpc.v1.cri".containerd.runtimes.runsc]
  runtime_type = "io.containerd.runsc.v1"
GVCONF

containerd_changed=false
if [ "$(sha256sum "$containerd_temp" | cut -d' ' -f1)" != "$(sha256sum "$CONTAINERD_TEMPLATE" 2>/dev/null | cut -d' ' -f1)" ]; then
  containerd_changed=true
  mv "$containerd_temp" "$CONTAINERD_TEMPLATE"
  chmod 644 "$CONTAINERD_TEMPLATE"
else
  rm -f "$containerd_temp"
fi

echo "gVisor containerd configuration written" 2>&1 | tee -a /var/log/hetzner-k3s.log

# Sampled before the installer: on a re-run of create the control plane is already running, and a
# changed containerd template only takes effect after k3s restarts.
k3s_active_before_install=false
systemctl is-active --quiet k3s 2>/dev/null && k3s_active_before_install=true{% endif %}

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

# Cluster domain override (cluster.local default)
if [ -n "{{ cluster_domain }}" ]; then
  CLUSTER_DOMAIN="--cluster-domain={{ cluster_domain }}"
else
  CLUSTER_DOMAIN=""
fi

# Install k3s
echo "Installing k3s..." 2>&1 | tee -a /var/log/hetzner-k3s.log

# See the worker script: a pipeline reports the status of `sh`, so the download is checked on its own.
installer=$(mktemp)
install_status_file=$(mktemp)
if curl --proto '=https' --tlsv1.2 -fsSL -o "$installer" https://get.k3s.io; then
{
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
    $COREDNS_PLUGIN \
    --write-kubeconfig-mode=644 \
    --node-name=$HOSTNAME \
    --cluster-cidr={{ cluster_cidr }} \
    --service-cidr={{ service_cidr }} \
    --cluster-dns={{ cluster_dns }} \
    $CLUSTER_DOMAIN \
    --kube-controller-manager-arg="bind-address=0.0.0.0" \
    $KUBE_PROXY_ARG \
    --kube-scheduler-arg="bind-address=0.0.0.0" \
    {{ master_taint }} {{ labels_and_taints }} {{ extra_args }} {{ etcd_arguments }} \
    $KUBELET_INSTANCE_ID \
    $FLANNEL_SETTINGS \
    $EMBEDDED_REGISTRY_MIRROR \
    $LOCAL_PATH_STORAGE_CLASS \
    --advertise-address=$PRIVATE_IP \
    --node-ip=$PRIVATE_IP \
    --node-external-ip=$PUBLIC_IP \
    {{ server }} {{ tls_sans }} < "$installer"; echo $? >"$install_status_file"; } 2>&1 | tee -a /var/log/hetzner-k3s.log
else
  echo "ERROR: could not download the k3s installer" 2>&1 | tee -a /var/log/hetzner-k3s.log
  echo 1 >"$install_status_file"
fi
rm -f "$installer"

# Check if installation was successful. PIPESTATUS is bash-only while cloud-init runs this with sh,
# so the status of the installer, not of tee, is written to a file.
install_status=$(cat "$install_status_file")
rm -f "$install_status_file"

if [ "$install_status" -ne 0 ]; then
  echo "ERROR: k3s installation failed" 2>&1 | tee -a /var/log/hetzner-k3s.log
  exit 1
fi

echo "k3s installation completed successfully" 2>&1 | tee -a /var/log/hetzner-k3s.log{% if gvisor_enabled == "true" %}

# The containerd template is read at startup only. A master with the CriticalAddonsOnly taint never
# runs gVisor pods, so it keeps the new config for its next restart instead of restarting the API
# server for nothing. A schedulable master restarts here, which is a brief API interruption.
if [ "$containerd_changed" = "true" ] && [ "$k3s_active_before_install" = "true" ]; then
  if [ "{{ masters_can_schedule }}" = "true" ]; then
    echo "containerd gVisor configuration changed; restarting k3s so runsc is loaded" 2>&1 | tee -a /var/log/hetzner-k3s.log
    systemctl restart k3s
  else
    echo "containerd gVisor configuration changed; it takes effect when k3s next restarts on this master" 2>&1 | tee -a /var/log/hetzner-k3s.log
  fi
fi{% endif %}

{% if additional_post_k3s_commands != "" %}
# Additional post-k3s commands
{{ additional_post_k3s_commands }}
{% endif %}

echo true >/etc/initialized
