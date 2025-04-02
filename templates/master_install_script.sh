touch /etc/initialized

HOSTNAME=$(hostname -f)
PUBLIC_IP=$(hostname -I | awk '{print $1}')

if [ "{{ private_network_enabled }}" = "true" ]; then
  if [ "{{ private_network_mode }}" = "hetzner" ]; then
    echo "Using Hetzner private network " >/var/log/hetzner-k3s.log
    SUBNET="{{ private_network_subnet }}"
  else
    echo "Using Tailscale private network " >/var/log/hetzner-k3s.log
    SUBNET="100.64.0.0/10"

    curl -fsSL https://tailscale.com/install.sh | sh && sudo tailscale up --login-server {{ tailscale_server_url }} --authkey={{ tailscale_auth_key }}

    printf '#!/bin/sh\n\nethtool -K %s tso off gso off gro off ufo off rx-udp-gro-forwarding off rx-gro-list off \n' "$(ip -o route get 8.8.8.8 | cut -f 5 -d " ")" | tee /etc/networkd-dispatcher/routable.d/50-tailscale
    chmod 755 /etc/networkd-dispatcher/routable.d/50-tailscale
    /etc/networkd-dispatcher/routable.d/50-tailscale

    cat > /etc/sysctl.d/99-disable-ipv6.conf << EOF
net.ipv6.conf.all.disable_ipv6 = 1
net.ipv6.conf.default.disable_ipv6 = 1
net.ipv6.conf.lo.disable_ipv6 = 1
net.ipv4.tcp_congestion_control=bbr
net.core.rmem_max=16777216
net.core.wmem_max=16777216
net.ipv4.tcp_rmem="4096 87380 16777216"
net.ipv4.tcp_wmem="4096 65536 16777216"
EOF
    sysctl -p /etc/sysctl.d/99-disable-ipv6.conf
  fi

  MAX_ATTEMPTS=30
  DELAY=10
  UP="false"

  for i in $(seq 1 $MAX_ATTEMPTS); do
    NETWORK_INTERFACE=$(
      ip -o link show |
        grep -E 'mtu (1450|1280)' |
        awk -F': ' '{print $2}' |
        grep -Ev 'cilium|br|flannel|docker|veth' |
        xargs -I {} bash -c 'ethtool {} &>/dev/null && echo {}' |
        head -n1
    )

    if [ ! -z "$NETWORK_INTERFACE" ]; then
      echo "Private network IP in subnet $SUBNET is up" 2>&1 | tee -a /var/log/hetzner-k3s.log
      UP="true"
      break
    fi
    echo "Waiting for private network IP in subnet $SUBNET to be available... (Attempt $i/$MAX_ATTEMPTS)" 2>&1 | tee -a /var/log/hetzner-k3s.log
    sleep $DELAY
  done

  if [ "$UP" = "false" ]; then
    echo "Timeout waiting for private network IP in subnet $SUBNET" 2>&1 | tee -a /var/log/hetzner-k3s.log
  fi

  PRIVATE_IP=$(
    ip -4 -o addr show dev "$NETWORK_INTERFACE" |
      awk '{print $4}' |
      cut -d'/' -f1 |
      head -n1
  )
else
  echo "Using public network " >/var/log/hetzner-k3s.log
  PRIVATE_IP="${PUBLIC_IP}"
  NETWORK_INTERFACE=" "
fi

if ([ "{{ cni }}" = "true" ] && [ "{{ cni_mode }}" = "flannel" ]) || ([ "{{ private_network_enabled }}" = "true" ] && [ "{{ private_network_mode }}" = "tailscale" ]); then
  FLANNEL_SETTINGS=" {{ flannel_backend }} --flannel-iface=$NETWORK_INTERFACE "
else
  FLANNEL_SETTINGS=" {{ flannel_backend }} "
fi

if [ "{{ embedded_registry_mirror_enabled }}" = "true" ]; then
  EMBEDDED_REGISTRY_MIRROR=" --embedded-registry "
else
  EMBEDDED_REGISTRY_MIRROR=" "
fi

if [ "{{ local_path_storage_class_enabled }}" = "true" ]; then
  LOCAL_PATH_STORAGE_CLASS=" "
else
  LOCAL_PATH_STORAGE_CLASS=" --disable local-storage "
fi

mkdir -p /etc/rancher/k3s

cat >/etc/rancher/k3s/registries.yaml <<EOF
mirrors:
  "*":
EOF

if [ "{{ private_network_enabled }}" = "true" ]; then
  CCM_AND_SERVICE_LOAD_BALANCER=" --disable-cloud-controller --disable servicelb "
else
  CCM_AND_SERVICE_LOAD_BALANCER=" "
fi

if [ "{{ private_network_enabled }}" = "true" ] && [ "{{ private_network_mode }}" = "tailscale" ]; then
  INSTANCE_ID=$(curl http://169.254.169.254/hetzner/v1/metadata/instance-id)
  TAILSCALE_KUBELET_ARGS=" --kubelet-arg=provider-id=hcloud://$INSTANCE_ID "
else
  TAILSCALE_KUBELET_ARGS=" "
fi

curl -sfL https://get.k3s.io | INSTALL_K3S_VERSION="{{ k3s_version }}" K3S_TOKEN="{{ k3s_token }}" {{ datastore_endpoint }} INSTALL_K3S_SKIP_START=false INSTALL_K3S_EXEC="server \
$CCM_AND_SERVICE_LOAD_BALANCER --disable traefik \
--disable metrics-server \
--write-kubeconfig-mode=644 \
--node-name=$HOSTNAME \
--cluster-cidr={{ cluster_cidr }} \
--service-cidr={{ service_cidr }} \
--cluster-dns={{ cluster_dns }} \
--kube-controller-manager-arg="bind-address=0.0.0.0" \
--kube-proxy-arg="metrics-bind-address=0.0.0.0" \
--kube-scheduler-arg="bind-address=0.0.0.0" \
{{ taint }} {{ extra_args }} {{ etcd_arguments }} $TAILSCALE_KUBELET_ARGS $FLANNEL_SETTINGS $EMBEDDED_REGISTRY_MIRROR $LOCAL_PATH_STORAGE_CLASS \
--advertise-address=$PRIVATE_IP \
--node-ip=$PRIVATE_IP \
--node-external-ip=$PUBLIC_IP \
{{ server }} {{ tls_sans }}" sh -

echo true >/etc/initialized
