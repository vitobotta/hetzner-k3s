touch /etc/initialized

HOSTNAME=$(hostname -f)
PUBLIC_IP=$(hostname -I | awk '{print $1}')

if [ "{{ private_network_enabled }}" = "true" ]; then
  if [ "{{ private_network_mode }}" = "hetzner" ]; then
    echo "Using Hetzner private network " >/var/log/hetzner-k3s.log
    SUBNET="{{ private_network_subnet }}"
  else
    echo "Using Tailscale private network " >/var/log/hetzner-k3s.log
    SUBNET="100.64.0.0/10"

    curl -fsSL https://tailscale.com/install.sh | sh && sudo tailscale up --login-server {{ tailscale_server_url }} --authkey={{ tailscale_auth_key }}
  fi

  MAX_ATTEMPTS=30
  DELAY=10
  UP="false"

  for i in $(seq 1 $MAX_ATTEMPTS); do
    NETWORK_INTERFACE=$(
      ip -o link show |
        grep -E 'mtu (1450|1280)' |
        awk -F': ' '{print $2}' |
        grep -Ev 'cilium|br|flannel|docker|veth' |
        xargs -I {} bash -c 'ethtool {} &>/dev/null && echo {}' |
        head -n1
    )

    if [ ! -z "$NETWORK_INTERFACE" ]; then
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

  PRIVATE_IP=$(
    ip -4 -o addr show dev "$NETWORK_INTERFACE" |
      awk '{print $4}' |
      cut -d'/' -f1 |
      head -n1
  )
  FLANNEL_SETTINGS=" --flannel-iface=$NETWORK_INTERFACE "
else
  echo "Using public network " >/var/log/hetzner-k3s.log
  PRIVATE_IP="${PUBLIC_IP}"
  FLANNEL_SETTINGS=" "
fi

mkdir -p /etc/rancher/k3s

cat >/etc/rancher/k3s/registries.yaml <<EOF
mirrors:
  "*":
EOF

curl -sfL https://get.k3s.io | K3S_TOKEN="{{ k3s_token }}" INSTALL_K3S_VERSION="{{ k3s_version }}" K3S_URL=https://{{ api_server_ip_address }}:6443 INSTALL_K3S_EXEC="agent \
--node-name=$HOSTNAME {{ extra_args }} \
--node-ip=$PRIVATE_IP \
--node-external-ip=$PUBLIC_IP \
$FLANNEL_SETTINGS " sh -

if [ "{{ private_network_enabled }}" = "true" ] && [ "{{ private_network_mode }}" = "tailscale" ]; then
  ethtool -K vxlan0 rx-udp-gro-forwarding on rx-gro-list off
fi

echo true >/etc/initialized
