fn_cloud="/var/lib/cloud/instance/boot-finished"
function await_cloud_init() {
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

mkdir -p /etc/rancher/k3s

cat > /etc/rancher/k3s/registries.yaml <<EOF
mirrors:
  "*":
EOF

curl -sfL https://get.k3s.io | K3S_TOKEN="{{ k3s_token }}" INSTALL_K3S_VERSION="{{ k3s_version }}" K3S_URL=https://{{ api_server_ip_address }}:6443 INSTALL_K3S_EXEC="agent \
--node-name=$HOSTNAME {{ extra_args }} \
--node-ip=$PRIVATE_IP \
--node-external-ip=$PUBLIC_IP \
$NETWORK_INTERFACE " sh -

echo true > /etc/initialized
