PRIVATE_IP=""

while [ -z "$PRIVATE_IP" ]; do
  PRIVATE_IP=$(ip -oneline -4 addr show scope global | tr -s ' ' | tr '/' ' ' | cut -f 2,4 -d ' ' | grep $(if lscpu | grep Vendor | grep -q Intel; then echo ens10 ; else echo enp7s0 ; fi) | awk '{print $2}')
  sleep 1
done && curl -sfL https://get.k3s.io | INSTALL_K3S_VERSION="{{ k3s_version }}" K3S_TOKEN="{{ k3s_token }}" INSTALL_K3S_EXEC="server \
--disable-cloud-controller \
--disable servicelb \
--disable traefik \
--disable local-storage \
--disable metrics-server \
--write-kubeconfig-mode=644 \
--node-name="$(hostname -f)" \
--cluster-cidr=10.244.0.0/16 \
--etcd-expose-metrics=true \
{{ flannel_wireguard }} \
--kube-controller-manager-arg="bind-address=0.0.0.0" \
--kube-proxy-arg="metrics-bind-address=0.0.0.0" \
--kube-scheduler-arg="bind-address=0.0.0.0" \
{{ taint }} {{ extra_args }} \
--kubelet-arg="cloud-provider=external" \
--advertise-address=$PRIVATE_IP \
--node-ip=$PRIVATE_IP \
--node-external-ip=$(hostname -I | awk '{print $1}') \
--flannel-iface="$(if lscpu | grep Vendor | grep -q Intel; then echo ens10 ; else echo enp7s0 ; fi)" \
{{ server }} {{ tls_sans }}" sh -
