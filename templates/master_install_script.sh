touch /etc/initialized

HOSTNAME=$(hostname -f)
PUBLIC_IP=$(hostname -I | awk '{print $1}')

if [ "{{ private_network_enabled }}" = "true" ]; then
  echo "Using private network " > /var/log/hetzner-k3s.log
  SUBNET="{{ private_network_subnet }}"
  SUBNET_PREFIX=$(echo $SUBNET | cut -d'/' -f1 | sed 's/\./\\./g' | sed 's/0$//')
  MAX_ATTEMPTS=30
  DELAY=10
  UP="false"

  for i in $(seq 1 $MAX_ATTEMPTS); do
    if ip -4 addr show | grep -q "inet $SUBNET_PREFIX"; then
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

  PRIVATE_IP=$(ip route get {{ private_network_test_ip }} | awk -F"src " 'NR==1{split($2,a," ");print a[1]}')
  NETWORK_INTERFACE=" --flannel-iface=$(ip route get {{ private_network_test_ip }} | awk -F"dev " 'NR==1{split($2,a," ");print a[1]}') "
else
  echo "Using public network " > /var/log/hetzner-k3s.log
  PRIVATE_IP="${PUBLIC_IP}"
  NETWORK_INTERFACE=" "
fi

if [ "{{ cni }}" = "true" ] && [ "{{ cni_mode }}" = "flannel" ]; then
  FLANNEL_SETTINGS=" {{ flannel_backend }} $NETWORK_INTERFACE "
else
  FLANNEL_SETTINGS=" {{ flannel_backend }} "
fi

if [ "{{ embedded_registry_mirror_enabled }}" = "true" ]; then
  EMBEDDED_REGISTRY_MIRROR=" --embedded-registry "
else
  EMBEDDED_REGISTRY_MIRROR=" "
fi

mkdir -p /etc/rancher/k3s

cat > /etc/rancher/k3s/registries.yaml <<EOF
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
{{ taint }} {{ extra_args }} {{ etcd_arguments }} {{ s3_arguments }} $FLANNEL_SETTINGS $EMBEDDED_REGISTRY_MIRROR \
--advertise-address=$PRIVATE_IP \
--node-ip=$PRIVATE_IP \
--node-external-ip=$PUBLIC_IP \
{{ server }} {{ tls_sans }}" sh -

echo true > /etc/initialized
