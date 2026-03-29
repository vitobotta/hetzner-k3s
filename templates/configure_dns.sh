#!/usr/bin/env python3
# Configure DNS servers in netplan and apply.
#
# Netplan uses the nameservers from the FIRST matching file per interface, so
# creating an overlay file (99-custom-dns.yaml) is ignored in practice. Instead
# we modify /etc/netplan/50-cloud-init.yaml in-place:
#   1. Ensure a nameservers.addresses list exists for every ethernet interface.
#   2. Remove any existing IPv6 addresses (identified by the colon separator)
#      to avoid mixing resolver families in a way that breaks NAT64 setups.
#   3. Append the configured DNS servers if not already present.
# Finally, `netplan apply` is called to activate the changes without a reboot.

import subprocess
import yaml

NETPLAN_FILE = "/etc/netplan/50-cloud-init.yaml"
DNS_SERVERS = {{ dns_servers_list }}

with open(NETPLAN_FILE) as f:
    config = yaml.safe_load(f)

ethernets = config.get("network", {}).get("ethernets", {})

for iface_cfg in ethernets.values():
    ns = iface_cfg.setdefault("nameservers", {})
    addrs = ns.setdefault("addresses", [])

    # Remove existing IPv6 nameservers so NAT64 resolvers take precedence
    addrs[:] = [a for a in addrs if ":" not in a]

    # Append each configured server if not already present
    for server in DNS_SERVERS:
        if server not in addrs:
            addrs.append(server)

with open(NETPLAN_FILE, "w") as f:
    yaml.dump(config, f, default_flow_style=False)

subprocess.check_call(["netplan", "apply"])
