# DNS configuration for /etc/k8s-resolv.conf (used by kubelet --resolv-conf)
# On IPv6-only nodes, 8.8.8.8 is unreachable. CoreDNS runs in the flannel pod
# network (IPv4-only) and cannot reach IPv6 DNS servers directly. We solve this
# by making systemd-resolved listen on the node's private IP, so both CoreDNS
# (from the pod network) and host-network pods can forward DNS through it.
# systemd-resolved then uses the host's IPv6 upstream DNS servers.
if [ "$IPV4_ENABLED" = "false" ]; then
  echo "IPv6-only node: configuring systemd-resolved DNS proxy on $PRIVATE_IP" 2>&1 | tee -a /var/log/hetzner-k3s.log
  mkdir -p /etc/systemd/resolved.conf.d
  cat > /etc/systemd/resolved.conf.d/k8s-dns-proxy.conf <<DNSEOF
[Resolve]
DNSStubListenerExtra=$PRIVATE_IP
DNSEOF
  systemctl restart systemd-resolved
  echo "nameserver $PRIVATE_IP" > /etc/k8s-resolv.conf
  echo "DNS proxy configured: pods will use $PRIVATE_IP:53 -> systemd-resolved -> IPv6 upstream" 2>&1 | tee -a /var/log/hetzner-k3s.log

  # Install clatd (464XLAT) to provide outbound IPv4 connectivity on IPv6-only nodes.
  # Without this, pods using flannel's IPv4 network (10.244.0.0/16) cannot reach
  # IPv4-only services (e.g. github.com) because the node has no IPv4 internet route.
  # clatd creates a clat interface that translates IPv4 packets into IPv6 via
  # Hetzner's NAT64 gateway, which then translates them back to IPv4.
  # The PLAT prefix is auto-detected via RFC 7050 (ipv4only.arpa DNS64 discovery).
  # This also provides the IPv4 default route that ClusterIP DNAT requires.
  #
  # clatd.conf, the systemd-networkd foreign-rules override, and the clatd
  # service retry override are written by cloud-init (see
  # Hetzner::Instance::CloudInitGenerator#clatd_files) before this script runs,
  # so no heredocs are needed here.
  echo "IPv6-only node: installing clatd (464XLAT) for outbound IPv4 connectivity" 2>&1 | tee -a /var/log/hetzner-k3s.log
  DEBIAN_FRONTEND=noninteractive apt-get install -y make tayga perl libnet-ip-perl libnet-dns-perl libjson-perl 2>&1 | tee -a /var/log/hetzner-k3s.log
  curl -fsSL https://github.com/toreanderson/clatd/archive/refs/tags/v2.1.0.tar.gz | tar -xz -C /tmp 2>&1 | tee -a /var/log/hetzner-k3s.log
  make -C /tmp/clatd-2.1.0 install 2>&1 | tee -a /var/log/hetzner-k3s.log
  rm -rf /tmp/clatd-2.1.0

  systemctl daemon-reload
  systemctl enable --now clatd 2>&1 | tee -a /var/log/hetzner-k3s.log
  echo "clatd installed and started — IPv4 default route via clat0 (NAT64)" 2>&1 | tee -a /var/log/hetzner-k3s.log
else
  printf '{{ k8s_resolv_nameservers }}' > /etc/k8s-resolv.conf
fi
