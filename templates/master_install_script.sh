curl -sfL https://get.k3s.io | INSTALL_K3S_VERSION="{{ k3s_version }}" K3S_TOKEN="{{ k3s_token }}" INSTALL_K3S_EXEC="server \
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
--advertise-address=$(hostname -I | awk '{print $2}') \
--node-ip=$(hostname -I | awk '{print $2}') \
--node-external-ip=$(hostname -I | awk '{print $1}') \
--flannel-iface="$(if lscpu | grep Vendor | grep -q Intel; then echo ens10 ; else echo enp7s0 ; fi)" \
{{ server }} {{ tls_sans }}" sh -
