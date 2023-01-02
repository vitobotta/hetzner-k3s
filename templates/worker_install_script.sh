curl -sfL https://get.k3s.io | K3S_TOKEN="{{ k3s_token }}" INSTALL_K3S_VERSION="{{ k3s_version }}" K3S_URL=https://{{ first_master_private_ip_address }}:6443 INSTALL_K3S_EXEC="agent \
  --node-name="$(hostname -f)" \
  --kubelet-arg="cloud-provider=external" \
  --node-ip=$(hostname -I | awk '{print $2}') \
  --node-external-ip=$(hostname -I | awk '{print $1}') \
  --flannel-iface={{ flannel_interface }}" sh -
