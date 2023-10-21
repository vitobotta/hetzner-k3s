touch /etc/initialized

if [[ $(< /etc/initialized) != "true" ]]; then
  systemctl restart NetworkManager || true
  dhclient eth1 -v || true
fi

HOSTNAME=$(hostname -f)
PRIVATE_IP=$(ip route get {{ private_network_test_ip }} | awk -F"src " 'NR==1{split($2,a," ");print a[1]}')
PUBLIC_IP=$(hostname -I | awk '{print $1}')
NETWORK_INTERFACE=$(ip route get {{ private_network_test_ip }} | awk -F"dev " 'NR==1{split($2,a," ");print a[1]}')

if [[ "{{ disable_flannel }}" = "true" ]]; then
  FLANNEL_SETTINGS=" --flannel-backend=none --disable-network-policy "
else
  FLANNEL_SETTINGS=" {{ flannel_backend }} --flannel-iface=$NETWORK_INTERFACE "
fi

curl -sfL https://get.k3s.io | INSTALL_K3S_VERSION="{{ k3s_version }}" K3S_TOKEN="{{ k3s_token }}" INSTALL_K3S_EXEC="server \
--disable-cloud-controller \
--disable servicelb \
--disable traefik \
--disable local-storage \
--disable metrics-server \
--write-kubeconfig-mode=644 \
--node-name=$HOSTNAME \
--cluster-cidr={{ cluster_cidr }} \
--service-cidr={{ service_cidr }} \
--cluster-dns={{ cluster_dns }} \
--etcd-expose-metrics=true \
--kube-controller-manager-arg="bind-address=0.0.0.0" \
--kube-proxy-arg="metrics-bind-address=0.0.0.0" \
--kube-scheduler-arg="bind-address=0.0.0.0" \
{{ taint }} {{ extra_args }} $FLANNEL_SETTINGS \
--kubelet-arg="cloud-provider=external" \
--advertise-address=$PRIVATE_IP \
--node-ip=$PRIVATE_IP \
--node-external-ip=$PUBLIC_IP \
{{ server }} {{ tls_sans }}" sh -

systemctl start k3s # on some OSes the service doesn't start automatically for some reason

echo true > /etc/initialized
