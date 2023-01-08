PRIVATE_IP=""

while [ -z "$PRIVATE_IP" ]; do
  PRIVATE_IP=$(ip route get 10.0.0.1 | awk -F"src " 'NR==1{split($2,a," ");print a[1]}')
  sleep 1
done && curl -sfL https://get.k3s.io | K3S_TOKEN="{{ k3s_token }}" INSTALL_K3S_VERSION="{{ k3s_version }}" K3S_URL=https://{{ first_master_private_ip_address }}:6443 INSTALL_K3S_EXEC="agent \
--node-name="$(hostname -f || echo \"{{ cluster_name }}-`dmidecode | grep -i uuid | awk '{print $2}' | cut -c1-8`\")" \
--kubelet-arg="cloud-provider=external" \
--node-ip=$PRIVATE_IP \
--node-external-ip=$(hostname -I | awk '{print $1}') \
--flannel-iface=$(ip route get 10.0.0.1 | awk -F"dev " 'NR==1{split($2,a," ");print a[1]}')" sh - && systemctl start k3s-agent

