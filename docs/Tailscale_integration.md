# Tailscale integration

hetzner-k3s supports first-class Tailscale integration, allowing you to provision cluster nodes with **no public IPv4 addresses** while still managing them over SSH through your [Tailscale](https://tailscale.com) tailnet. Once Tailscale is installed and authenticated during cloud-init, all subsequent provisioning SSH connections are routed through MagicDNS hostnames rather than public IPs.

This is the recommended approach for hardened clusters where you want nodes to be unreachable from the public internet while retaining full management capability.

## How it works

When `use_tailscale: true` is set, hetzner-k3s injects the following into each node's cloud-init bootstrap sequence (immediately after `hostnamectl` sets the hostname):

1. Installs Tailscale via the official install script (`curl -fsSL https://tailscale.com/install.sh | sh`)
2. Authenticates and registers the node with your tailnet (`tailscale up --authkey=... --hostname=$(hostname) --accept-routes`)
3. Disables Tailscale's MagicDNS (`tailscale set --accept-dns=false`) so NAT64 resolvers handle all DNS on IPv6-only nodes
4. Deploys a persistent nftables fix service for ClusterIP DNAT compatibility (see [IPv6-only runtime fixes](#ipv6-only-runtime-fixes))

After cloud-init completes, hetzner-k3s uses the MagicDNS hostname (`<instance-name>.<tailnet-name>.ts.net`) for all SSH connections instead of the node's public or private IP address.

The Tailscale machine name is guaranteed to match the Hetzner instance name because `tailscale up --hostname=$(hostname)` runs after `hostnamectl` has already set the hostname from the Hetzner metadata API.

## Prerequisites

- A Tailscale account with MagicDNS enabled (Settings > DNS > Enable MagicDNS)
- A **reusable, pre-approved** auth key (not ephemeral -- nodes are long-lived servers). Tagged keys are recommended for ACL scoping. Generate one at https://login.tailscale.com/admin/settings/keys.
- The machine running hetzner-k3s must itself be connected to the same tailnet, so it can reach nodes via MagicDNS once they boot.

## Firewall note

Tailscale requires **no inbound firewall rules**. It establishes connections outbound only (TCP 443 for coordination, UDP 41641 for direct connections, UDP 3478 for DERP relay fallback). Your `allowed_networks` configuration is unaffected.

## Configuration

Add the following to your `cluster.yaml`:

```yaml
networking:
  ssh:
    port: 22
    use_agent: true
    public_key_path: "~/.ssh/id_ed25519.pub"
    private_key_path: "~/.ssh/id_ed25519"
    use_tailscale: true
    tailscale_hostname_suffix: "my-tailnet.ts.net"
    # tailscale_auth_key: "tskey-auth-..."  # prefer TAILSCALE_AUTH_KEY env var instead
  public_network:
    ipv4: false
    ipv6: true   # required when ipv4 is disabled so nodes can reach the Tailscale coordination server
  private_network:
    enabled: true  # recommended for inter-node traffic
```

### Auth key

The Tailscale auth key can be provided in two ways (env var takes precedence):

| Method | How |
|--------|-----|
| Environment variable (recommended) | `export TAILSCALE_AUTH_KEY="tskey-auth-..."` |
| Config file | `tailscale_auth_key: "tskey-auth-..."` in the `ssh:` block |

### Required fields when `use_tailscale: true`

| Field | Description |
|-------|-------------|
| `tailscale_hostname_suffix` | Your tailnet's MagicDNS domain, e.g. `my-tailnet.ts.net`. Find it in the Tailscale admin console under DNS. |
| `tailscale_auth_key` / `TAILSCALE_AUTH_KEY` | A reusable pre-approved auth key. |

### IPv6 requirement

When `ipv4: false`, nodes need `ipv6: true` so they can reach the Tailscale coordination server (`controlplane.tailscale.com`) during boot. hetzner-k3s will validate this and report an error if both are disabled with Tailscale enabled.

### DNS servers (NAT64 for IPv6-only nodes)

When running IPv6-only nodes (`ipv4: false, ipv6: true`), some upstream services like GitHub only have IPv4 addresses. The k3s installer downloads binaries from GitHub, so IPv6-only nodes need **NAT64 DNS resolvers** that synthesize AAAA records for IPv4-only hosts.

Use the `dns_servers` field under `networking:` to configure custom DNS servers. These are injected into the existing netplan config (`/etc/netplan/50-cloud-init.yaml`) during cloud-init and applied with `netplan apply`, so they survive reboots and network reconfigurations:

```yaml
networking:
  dns_servers:
    - 2a01:4f9:c010:3f02::1   # NAT64 resolver
    - 2a00:1098:2c::1          # NAT64 resolver
    - 2a00:1098:2b::1          # NAT64 resolver
  public_network:
    ipv4: false
    ipv6: true
```

> **Note:** Tailscale's own installation (`tailscale.com` and `pkgs.tailscale.com`) supports IPv6 natively, so Tailscale will install correctly even before NAT64 DNS is active. The NAT64 resolvers are primarily needed for the k3s installer which downloads from GitHub.

When both Tailscale and IPv6-only are enabled, hetzner-k3s runs `tailscale set --accept-dns=false` to disable Tailscale's MagicDNS. Without this, MagicDNS intercepts DNS queries and returns IPv4 A records that IPv6-only nodes cannot use. With MagicDNS disabled, the NAT64 resolvers in `dns_servers` handle all queries, including synthesising IPv6 addresses for IPv4-only hosts like `github.com`. Note that tailnet MagicDNS hostnames (`node.tailnet.ts.net`) are still reachable via Tailscale's overlay network -- only DNS resolution is affected.

## IPv6-only runtime fixes

Running k3s on IPv6-only Hetzner nodes with Tailscale requires three automatic fixes that hetzner-k3s applies during provisioning. These address fundamental incompatibilities between Tailscale's firewall, IPv6-only networking, and Kubernetes ClusterIP services.

### 1. Tailscale nftables ts-input chain fix

**Problem:** IPv6-only Hetzner nodes receive a CGNAT IPv4 address in `100.64.0.0/10`. Tailscale's firewall adds an nftables rule in its `ts-input` chain that drops all traffic from `100.64.0.0/10` on any interface except `tailscale0`. When a host-network pod sends traffic to a ClusterIP (e.g. `10.43.0.1:443`), kube-proxy DNATs it to a local endpoint and the packet loops through the loopback interface. The `ts-input` chain sees source `100.64.0.0/10` on interface `lo` (not `tailscale0`) and drops it.

**Fix:** A persistent systemd service (`tailscale-nftables-fix.service`) deployed via cloud-init that inserts `nft insert rule ip filter ts-input iifname lo ct status dnat accept` at the top of the `ts-input` chain. The service monitors every 30 seconds and re-applies the rule if Tailscale rewrites its firewall rules.

> **Note:** Standard `iptables` commands do not work here because Tailscale manages the `ts-input` chain via nftables on Ubuntu 24.04. Only `nft` commands can modify it.

### 2. DNS resolution for CoreDNS on IPv6-only nodes

**Problem:** The default `/etc/k8s-resolv.conf` uses `nameserver 8.8.8.8`, which is unreachable on IPv6-only nodes (no IPv4 internet route). Simply changing to IPv6 DNS servers doesn't work either -- CoreDNS runs in the flannel pod network (`10.244.0.x`) which is IPv4-only and cannot reach IPv6 addresses.

**Fix:** During k3s installation, hetzner-k3s configures `systemd-resolved` to listen on the node's private network IP (via `DNSStubListenerExtra`) and writes `/etc/k8s-resolv.conf` with that private IP as the nameserver. This way:
- CoreDNS (in the IPv4-only pod network) forwards DNS to `$PRIVATE_IP:53` via flannel routing
- `systemd-resolved` answers using the host's IPv6 upstream DNS servers (the NAT64 resolvers)
- Host-network pods with `dnsPolicy: Default` also use this path

### 3. IPv4 default route for ClusterIP DNAT

**Problem:** IPv6-only Hetzner nodes have no IPv4 default route. The kernel returns `ENETUNREACH` immediately for any IPv4 destination without a specific route, including ClusterIP addresses (`10.43.0.0/16`). Packets never reach nftables, so kube-proxy's DNAT rules in the OUTPUT chain cannot rewrite them to local pod endpoints. This causes all pods that contact the API server (CCM, CoreDNS, etc.) to fail with `dial tcp 10.43.0.1:443: connect: network is unreachable`.

**Fix:** Before k3s installation, hetzner-k3s adds a default IPv4 route via Hetzner's standard gateway (`172.31.1.1`) with a high metric (500). This gateway is always present on IPv6-only nodes but doesn't forward IPv4 internet traffic -- it only handles local/metadata routing. The route prevents `ENETUNREACH` so that nftables can process packets and DNAT ClusterIP traffic to local endpoints. The public interface is auto-detected (Intel servers use `eth0`, ARM servers use `enp1s0`).

## Full example cluster.yaml (IPv6-only nodes)

```yaml
cluster_name: my-cluster
kubeconfig_path: "./kubeconfig.yaml"
k3s_version: v1.32.3+k3s1
public_ssh_key_path: "~/.ssh/id_ed25519.pub"
private_ssh_key_path: "~/.ssh/id_ed25519"

networking:
  ssh:
    port: 22
    use_agent: true
    public_key_path: "~/.ssh/id_ed25519.pub"
    private_key_path: "~/.ssh/id_ed25519"
    use_tailscale: true
    tailscale_hostname_suffix: "my-tailnet.ts.net"
  public_network:
    ipv4: false
    ipv6: true
  private_network:
    enabled: true
    subnet: 10.1.0.0/16
  allowed_networks:
    ssh:
      - 0.0.0.0/0
    api:
      - 0.0.0.0/0
  dns_servers:
    - 2a01:4f9:c010:3f02::1
    - 2a00:1098:2c::1
    - 2a00:1098:2b::1

masters_pool:
  instance_type: cax11
  instance_count: 3
  location: nbg1

worker_node_pools:
  - name: workers
    instance_type: cax21
    instance_count: 3
    location: nbg1
```

Run with the auth key exported:

```bash
export TAILSCALE_AUTH_KEY="tskey-auth-..."
hetzner-k3s create --config cluster.yaml
```

## Bootstrap sequence

For reference, here is the order of operations during node provisioning when Tailscale is enabled:

1. **DNS servers netplan update** -- modifies `/etc/netplan/50-cloud-init.yaml` and runs `netplan apply` (if `dns_servers` is configured)
2. **Hostname** -- `hostnamectl set-hostname <name>` from Hetzner metadata
3. **Admin user** -- creates `admin` user with SSH key and passwordless sudo
4. **Tailscale install** -- `curl -fsSL https://tailscale.com/install.sh | sh`
5. **Tailscale join** -- `tailscale up --authkey=... --hostname=$(hostname) --accept-routes`
6. **Disable MagicDNS** -- `tailscale set --accept-dns=false` so NAT64 resolvers handle all DNS
7. **nftables fix service** -- `systemctl enable --now tailscale-nftables-fix.service`
8. **SSH configuration** -- `/etc/configure_ssh.sh`
9. **DNS proxy** (IPv6-only) -- configures `systemd-resolved` to listen on private IP, writes `/etc/k8s-resolv.conf`
10. **IPv4 default route** (IPv6-only) -- adds route via `172.31.1.1` for ClusterIP DNAT
11. **k3s installation** -- downloads and starts k3s

After step 5, the node is reachable on the tailnet as `<instance-name>.<tailnet-name>.ts.net`. hetzner-k3s retries SSH in a loop (up to 60 attempts for Tailscale mode) which naturally handles the short delay while steps 4-5 complete.

## Cleanup note

When deleting a cluster, hetzner-k3s deletes the Hetzner cloud instances but does **not** remove the corresponding nodes from your Tailscale tailnet. You should manually remove stale nodes from the [Tailscale admin console](https://login.tailscale.com/admin/machines) after cluster deletion. If you redeploy with the same hostnames while stale entries exist, Tailscale will append a `-1` suffix to the new nodes' DNS names, which will prevent hetzner-k3s from finding them.
