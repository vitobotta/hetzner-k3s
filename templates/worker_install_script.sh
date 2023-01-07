PRIVATE_IP=""

while [ -z "$PRIVATE_IP" ]; do
  PRIVATE_IP=$(ip -oneline -4 addr show scope global | tr -s ' ' | tr '/' ' ' | cut -f 2,4 -d ' ' | grep $(if lscpu | grep Vendor | grep -q Intel; then echo ens10 ; else echo enp7s0 ; fi) | awk '{print $2}')
  sleep 1
done && curl -sfL https://get.k3s.io | K3S_TOKEN="{{ k3s_token }}" INSTALL_K3S_VERSION="{{ k3s_version }}" K3S_URL=https://{{ first_master_private_ip_address }}:6443 INSTALL_K3S_EXEC="agent \
--node-name="$(hostname -f)" \
--kubelet-arg="cloud-provider=external" \
--node-ip=$PRIVATE_IP \
--node-external-ip=$(hostname -I | awk '{print $1}') \
--flannel-iface=$(if lscpu | grep Vendor | grep -q Intel; then echo ens10 ; else echo enp7s0 ; fi)" sh -
