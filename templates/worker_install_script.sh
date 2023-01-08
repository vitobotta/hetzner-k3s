cat <<-EOF > /etc/worker_install_script.sh
PRIVATE_IP=$(ip route get 10.0.0.1 | awk -F"src " 'NR==1{split($2,a," ");print a[1]}')

curl -sfL https://get.k3s.io | K3S_TOKEN="{{ k3s_token }}" INSTALL_K3S_VERSION="{{ k3s_version }}" K3S_URL=https://{{ first_master_private_ip_address }}:6443 INSTALL_K3S_EXEC="agent \
--node-name="$(hostname -f || echo \"{{ cluster_name }}-`dmidecode | grep -i uuid | awk '{print $2}' | cut -c1-8`\")" \
--kubelet-arg="cloud-provider=external" \
--node-ip=\$PRIVATE_IP \
--node-external-ip=$(hostname -I | awk '{print $1}') \
--flannel-iface=$(ip route get 10.0.0.1 | awk -F"dev " 'NR==1{split($2,a," ");print a[1]}')" sh - >> /etc/worker_install_script.log 2>&1

echo true > /etc/ready
EOF

chmod +x /etc/worker_install_script.sh

cat <<EOF > /etc/systemd/system/initialize-k3s.service
[Unit]
Description=Set up k3s

[Service]
Type=oneshot
ExecStart=/bin/bash /etc/worker_install_script.sh
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


