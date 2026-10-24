#!/bin/bash
# Configure DNS servers in netplan and apply.
#
# Netplan uses the nameservers from the FIRST matching file per interface, so
# creating an overlay file (99-custom-dns.yaml) is ignored in practice. Instead
# we rewrite /etc/netplan/50-cloud-init.yaml in-place, inserting a
# `nameservers: / addresses: [...]` block directly under each interface entry
# in the `network.ethernets` map.
#
# This only applies to netplan-based systems (Ubuntu/Debian images). On other
# distros (AlmaLinux, Rocky, CentOS Stream, Fedora, ...) netplan isn't present,
# so this script is a no-op there - DNS is left to the OS default (DHCP).
#
# This script is only ever run once per instance via cloud-init's runcmd
# (which cloud-init guarantees runs only on first boot), so no idempotent
# merge/removal of a previous run's block is required.

set -euo pipefail

NETPLAN_FILE="/etc/netplan/50-cloud-init.yaml"
DNS_SERVERS="{{ dns_servers_list }}" # space-separated list, e.g. "8.8.8.8" or "2a01:... 2a00:..."

if [ ! -f "$NETPLAN_FILE" ]; then
  echo "configure-dns: $NETPLAN_FILE not found (not a netplan-managed system) - skipping DNS configuration"
  exit 0
fi

awk -v dns_servers="$DNS_SERVERS" '
BEGIN {
  n = split(dns_servers, servers, " ")
  in_ethernets = 0
  ethernets_indent = -1
  iface_indent = -1
  step = 4
}
{
  match($0, /^[ ]*/)
  indent = RLENGTH

  if ($0 ~ /^[ ]*ethernets:[ ]*$/) {
    in_ethernets = 1
    ethernets_indent = indent
    iface_indent = -1
    print
    next
  }

  if (in_ethernets && indent <= ethernets_indent) {
    in_ethernets = 0
  }

  # Auto-detect the indent step from the first line inside "ethernets:"
  # (the first interface header), since cloud-init/netplan may use either
  # 2-space or 4-space indentation depending on version/distro.
  if (in_ethernets && iface_indent == -1 && indent > ethernets_indent) {
    iface_indent = indent
    step = iface_indent - ethernets_indent
  }

  print

  # Interface header lines are the direct children of "ethernets:"
  # (e.g. "  eth0:" or "        eth0:"), matched at the detected indent step.
  if (in_ethernets && indent == iface_indent && $0 ~ /:[ ]*$/) {
    pad1 = sprintf("%*s", iface_indent + step, "")
    pad2 = sprintf("%*s", iface_indent + step * 2, "")
    print pad1 "nameservers:"
    print pad2 "addresses:"
    for (i = 1; i <= n; i++) {
      print pad2 "  - " servers[i]
    }
  }
}
' "$NETPLAN_FILE" >"${NETPLAN_FILE}.new"

mv "${NETPLAN_FILE}.new" "$NETPLAN_FILE"

# Prevent cloud-init from regenerating netplan on subsequent reboots and
# overwriting the DNS servers we just configured.
CLOUD_INIT_NET_DISABLE="/etc/cloud/cloud.cfg.d/99-disable-network-config.cfg"
mkdir -p "$(dirname "$CLOUD_INIT_NET_DISABLE")"
echo "network: {config: disabled}" >"$CLOUD_INIT_NET_DISABLE"

netplan apply
