cat <<-EOF > /etc/master_install_script.sh
PRIVATE_IP=$(ip route get 10.0.0.1 | awk -F"src " 'NR==1{split($2,a," ");print a[1]}')

curl -sfL https://get.k3s.io | INSTALL_K3S_VERSION="{{ k3s_version }}" K3S_TOKEN="{{ k3s_token }}" INSTALL_K3S_EXEC="server \
--disable-cloud-controller \
--disable servicelb \
--disable traefik \
--disable local-storage \
--disable metrics-server \
--write-kubeconfig-mode=644 \
--node-name="$(hostname -f || echo \"{{ cluster_name }}-`dmidecode | grep -i uuid | awk '{print $2}' | cut -c1-8`\")" \
--cluster-cidr=10.244.0.0/16 \
--etcd-expose-metrics=true \
{{ flannel_wireguard }} \
--kube-controller-manager-arg="bind-address=0.0.0.0" \
--kube-proxy-arg="metrics-bind-address=0.0.0.0" \
--kube-scheduler-arg="bind-address=0.0.0.0" \
{{ taint }} {{ extra_args }} \
--kubelet-arg="cloud-provider=external" \
--advertise-address=\$PRIVATE_IP \
--node-ip=\$PRIVATE_IP \
--node-external-ip=$(hostname -I | awk '{print $1}') \
--flannel-iface="$(ip route get 10.0.0.1 | awk -F"dev " 'NR==1{split($2,a," ");print a[1]}')" \
{{ server }} {{ tls_sans }}" sh - >> /etc/master_install_script.log 2>&1

echo true > /etc/ready
EOF

chmod +x /etc/master_install_script.sh

cat <<EOF > /etc/systemd/system/initialize-k3s.service
[Unit]
Description=Set up k3s

[Service]
Type=oneshot
ExecStart=/bin/bash /etc/master_install_script.sh
EOF

cat <<EOF > /etc/systemd/system/initialize-k3s.timer
[Unit]
Description=Set up k3s

[Timer]
OnBootSec=1s
Unit=initialize-k3s.service

[Install]
WantedBy=timers.target
EOF

systemctl daemon-reload
systemctl enable initialize-k3s.timer


