touch /etc/initialized

HOSTNAME=$(hostname -f)
PUBLIC_IP=$(hostname -I | awk '{print $1}')

if [ "{{ private_network_enabled }}" = "true" ]; then
  echo "Using private network " >/var/log/hetzner-k3s.log
  SUBNET="{{ private_network_subnet }}"
  MAX_ATTEMPTS=30
  DELAY=10
  UP="false"

  for i in $(seq 1 $MAX_ATTEMPTS); do
    NETWORK_INTERFACE=$(
      ip -o link show |
        grep -w 'mtu 1450' |
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

if [ "{{ cni }}" = "true" ] && [ "{{ cni_mode }}" = "flannel" ]; then
  FLANNEL_SETTINGS=" {{ flannel_backend }} --flannel-iface=$NETWORK_INTERFACE "
else
  FLANNEL_SETTINGS=" {{ flannel_backend }} "
fi

if [ "{{ embedded_registry_mirror_enabled }}" = "true" ]; then
  EMBEDDED_REGISTRY_MIRROR=" --embedded-registry "
else
  EMBEDDED_REGISTRY_MIRROR=" "
fi

mkdir -p /etc/rancher/k3s

cat >/etc/rancher/k3s/registries.yaml <<EOF
mirrors:
  "*":
EOF

curl -sfL https://get.k3s.io | INSTALL_K3S_VERSION="{{ k3s_version }}" K3S_TOKEN="{{ k3s_token }}" {{ datastore_endpoint }} INSTALL_K3S_EXEC="server \
--disable-cloud-controller \
--disable servicelb \
--disable traefik \
--disable metrics-server \
--write-kubeconfig-mode=644 \
--node-name=$HOSTNAME \
--cluster-cidr={{ cluster_cidr }} \
--service-cidr={{ service_cidr }} \
--cluster-dns={{ cluster_dns }} \
--kube-controller-manager-arg="bind-address=0.0.0.0" \
--kube-proxy-arg="metrics-bind-address=0.0.0.0" \
--kube-scheduler-arg="bind-address=0.0.0.0" \
{{ taint }} {{ extra_args }} {{ etcd_arguments }} $FLANNEL_SETTINGS $EMBEDDED_REGISTRY_MIRROR \
--advertise-address=$PRIVATE_IP \
--node-ip=$PRIVATE_IP \
--node-external-ip=$PUBLIC_IP \
{{ server }} {{ tls_sans }}" sh -

echo true >/etc/initialized
