#!/bin/bash
# Fix Tailscale nftables ts-input chain for DNAT/ClusterIP traffic.
#
# On IPv6-only Hetzner nodes, the primary IPv4 address is a CGNAT address
# in 100.64.0.0/10. Tailscale's firewall adds an nftables rule in its
# ts-input chain that drops all traffic from 100.64.0.0/10 on any interface
# except tailscale0. When a host-network pod sends traffic to a ClusterIP
# (e.g. 10.43.0.1:443), kube-proxy DNATs it to a local endpoint and the
# packet loops through the loopback interface. The ts-input chain then sees
# source 100.64.0.0/10 on interface lo (not tailscale0) and drops it.
#
# Fix: insert a rule at the top of ts-input that accepts loopback traffic
# which has been DNAT'd (conntrack status). This script waits for the
# ts-input chain to exist, inserts the rule, then monitors periodically
# in case Tailscale rewrites its firewall rules.

# Wait for Tailscale to create the ts-input chain
while ! nft list chain ip filter ts-input &>/dev/null; do
  sleep 2
done

apply_fix() {
  # Check if our rule already exists (look for "lo" + "ct status dnat" + "accept")
  if ! nft list chain ip filter ts-input 2>/dev/null | grep -q 'iifname "lo" ct status dnat accept'; then
    nft insert rule ip filter ts-input iifname lo ct status dnat accept
    echo "$(date): Inserted ts-input DNAT accept rule" >> /var/log/tailscale-nftables-fix.log
  fi
}

apply_fix

# Monitor: re-apply if Tailscale rewrites its firewall rules
while true; do
  sleep 30
  apply_fix
done
