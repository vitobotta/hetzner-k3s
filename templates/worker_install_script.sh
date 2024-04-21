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

curl -sfL https://get.k3s.io | K3S_TOKEN="{{ k3s_token }}" INSTALL_K3S_VERSION="{{ k3s_version }}" K3S_URL=https://{{ api_server_ip_address }}:6443 INSTALL_K3S_EXEC="agent \
--node-name=$HOSTNAME {{ extra_args }} \
--node-ip=$PRIVATE_IP \
--node-external-ip=$PUBLIC_IP \
$NETWORK_INTERFACE " sh -

systemctl start k3s-agent # on some OSes the service doesn't start automatically for some reason

echo true > /etc/initialized
