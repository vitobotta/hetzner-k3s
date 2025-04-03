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

    printf '#!/bin/sh\n\nethtool -K %s tso off gso off gro off ufo off rx-udp-gro-forwarding off rx-gro-list off \n' "$(ip -o route get 8.8.8.8 | cut -f 5 -d " ")" | tee /etc/networkd-dispatcher/routable.d/50-tailscale
    chmod 755 /etc/networkd-dispatcher/routable.d/50-tailscale
    /etc/networkd-dispatcher/routable.d/50-tailscale

        cat > /etc/sysctl.d/99-disable-ipv6.conf << EOF
net.ipv6.conf.all.disable_ipv6 = 1
net.ipv6.conf.default.disable_ipv6 = 1
net.ipv6.conf.lo.disable_ipv6 = 1
net.core.rmem_max=26214400
net.core.wmem_max=26214400
net.core.rmem_default=1048576
net.core.wmem_default=1048576
net.ipv4.tcp_rmem="4096 87380 16777216"
net.ipv4.tcp_wmem="4096 65536 16777216"
net.ipv4.tcp_congestion_control=bbr
net.ipv4.tcp_mtu_probing=1
net.core.somaxconn=65535
net.ipv4.tcp_max_syn_backlog=65535
net.ipv4.udp_mem="65536 131072 262144"
net.ipv4.udp_rmem_min=16384
net.ipv4.udp_wmem_min=16384
net.ipv4.tcp_slow_start_after_idle=0
net.core.netdev_max_backlog=65536
net.ipv4.tcp_congestion_control=bbr
EOF
    sysctl -p /etc/sysctl.d/99-disable-ipv6.conf
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

if [ "{{ private_network_enabled }}" = "false" ]; then
  INSTANCE_ID=$(curl http://169.254.169.254/hetzner/v1/metadata/instance-id)
  KUBELET_INSTANCE_ID=" --kubelet-arg=provider-id=hcloud://$INSTANCE_ID "
fi

curl -sfL https://get.k3s.io | K3S_TOKEN="{{ k3s_token }}" INSTALL_K3S_VERSION="{{ k3s_version }}" K3S_URL=https://{{ api_server_ip_address }}:6443 INSTALL_K3S_EXEC="agent \
--node-name=$HOSTNAME {{ extra_args }} \
--node-ip=$PRIVATE_IP \
--node-external-ip=$PUBLIC_IP \
$KUBELET_INSTANCE_ID $FLANNEL_SETTINGS " sh -

echo true >/etc/initialized
