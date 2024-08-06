fn_cloud="/var/lib/cloud/instance/boot-finished"
function await_cloud_init {
  echo "🕒 Awaiting cloud config (may take a minute...)"
  while true; do
    for _ in $(seq 1 10); do
      test -f $fn_cloud && return
      sleep 1
    done
    echo -n "."
  done
}
test -f $fn_cloud || await_cloud_init
echo "Cloud init finished: $(cat $fn_cloud)"


touch /etc/initialized

if [[ $(< /etc/initialized) != "true" ]]; then
  systemctl restart NetworkManager || true
  dhclient eth1 -v || true
fi

HOSTNAME=$(hostname -f)
PUBLIC_IP=$(hostname -I | awk '{print $1}')

if [[ "{{ private_network_enabled }}" = "true" ]]; then
  PRIVATE_IP=$(ip route get {{ private_network_test_ip }} | awk -F"src " 'NR==1{split($2,a," ");print a[1]}')
  NETWORK_INTERFACE=" --flannel-iface=$(ip route get {{ private_network_test_ip }} | awk -F"dev " 'NR==1{split($2,a," ");print a[1]}') "
else
  PRIVATE_IP="${PUBLIC_IP}"
  NETWORK_INTERFACE=" "
fi

if [[ "{{ cni }}" = "true" ]] && [[ "{{ cni_mode }}" = "flannel" ]]; then
  FLANNEL_SETTINGS=" {{ flannel_backend }} $NETWORK_INTERFACE "
else
  FLANNEL_SETTINGS=" {{ flannel_backend }} "
fi

if [[ "{{ embedded_registry_mirror_enabled }}" = "true" ]]; then
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
{{ taint }} {{ extra_args }} {{ etcd_arguments }} $FLANNEL_SETTINGS $EMBEDDED_REGISTRY_MIRROR \
--advertise-address=$PRIVATE_IP \
--node-ip=$PRIVATE_IP \
--node-external-ip=$PUBLIC_IP \
{{ server }} {{ tls_sans }}" sh -

echo true > /etc/initialized
