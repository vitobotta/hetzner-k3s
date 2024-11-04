touch /etc/initialized

HOSTNAME=$(hostname -f)
PUBLIC_IP=$(hostname -I | awk '{print $1}')

if [ "{{ private_network_enabled }}" = "true" ]; then
  echo "Using private network " > /var/log/hetzner-k3s.log
  SUBNET="{{ private_network_subnet }}"
  SUBNET_PREFIX=$(echo $SUBNET | cut -d'/' -f1 | sed 's/\./\\./g' | sed 's/0$//')
  MAX_ATTEMPTS=30
  DELAY=10
  UP="false"

  for i in $(seq 1 $MAX_ATTEMPTS); do
    if ip -4 addr show | grep -q "inet $SUBNET_PREFIX"; then
      echo "Private network IP in subnet $SUBNET is up" 2>&1 | tee -a /var/log/hetzner-k3s.log
      UP="true"
      break
    fi
    echo "Waiting for private network IP in subnet $SUBNET to be available... (Attempt $i/$MAX_ATTEMPTS)" 2>&1 | tee -a /var/log/hetzner-k3s.log
    sleep $DELAY
  done

  if [ "$UP" = "false" ]; then
    echo "Timeout waiting for private network IP in subnet $SUBNET" 2>&1 | tee -a /var/log/hetzner-k3s.log
  fi

  PRIVATE_IP=$(ip route get {{ private_network_test_ip }} | awk -F"src " 'NR==1{split($2,a," ");print a[1]}')
  NETWORK_INTERFACE=" --flannel-iface=$(ip route get {{ private_network_test_ip }} | awk -F"dev " 'NR==1{split($2,a," ");print a[1]}') "
else
  echo "Using public network " > /var/log/hetzner-k3s.log
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
