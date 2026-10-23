# Tailscale integration

hetzner-k3s can install [Tailscale](https://tailscale.com) on every cluster node during provisioning and join them to your tailnet. This gives you a private administrative path to the nodes (SSH) and to the Kubernetes API, without exposing them to the public internet or maintaining CIDR allowlists for changing IPs (home, coworking, travel).

When enabled:

1. Each node installs Tailscale in cloud-init and joins the tailnet as `<instance-name>.<hostname_suffix>` (MagicDNS name).
2. All SSH connections made by hetzner-k3s itself (provisioning, upgrades, `run` commands) go through the tailnet instead of public or private IPs.
3. The API server certificate gets a TLS SAN for each master's Tailscale hostname, and the generated kubeconfig points to `https://<first-master>.<hostname_suffix>:6443`.

## Prerequisites

- A Tailscale account with MagicDNS enabled (Settings > DNS > Enable MagicDNS).
- A **reusable, pre-approved** auth key. Nodes are long-lived servers, so ephemeral keys are not suitable. Tagged keys are recommended for ACL scoping (e.g. `tag:k8s-nodes`). Generate one at <https://login.tailscale.com/admin/settings/keys>.
- The machine running hetzner-k3s must be connected to the same tailnet and have the `tailscale` CLI installed, since hetzner-k3s checks peer registration with `tailscale status` before connecting.

## Configuration

```yaml
networking:
  tailscale:
    enabled: true
    hostname_suffix: "my-tailnet.ts.net" # your tailnet's MagicDNS domain, found in the admin console under DNS
    # auth_key: "tskey-auth-..." # optional: defaults to the TAILSCALE_AUTH_KEY environment variable
```

The auth key can be supplied in two ways:

| Method | How |
|--------|-----|
| Environment variable (recommended) | `export TAILSCALE_AUTH_KEY="tskey-auth-..."` |
| Config file | `auth_key: "tskey-auth-..."` in the `tailscale:` block |

The key is written to `/run/tailscale-authkey` (mode `0600`, tmpfs) on each node during cloud-init and deleted immediately after `tailscale up` runs. It never touches the node's persistent disk.

## Locking down public access

Tailscale requires **no inbound firewall rules**: connections are established outbound only. Once nodes are reachable over the tailnet, you can restrict the public SSH and API firewalls, since the current-IP validation in `allowed_networks` is skipped when Tailscale is enabled:

```yaml
networking:
  tailscale:
    enabled: true
    hostname_suffix: "my-tailnet.ts.net"
  allowed_networks:
    ssh:
      - 10.0.0.0/8 # effectively blocks public SSH; real access goes over the tailnet
    api:
      - 10.0.0.0/8 # same for the Kubernetes API on port 6443
```

With this setup, `kubectl` works from any machine connected to the tailnet, because the kubeconfig points to the master's MagicDNS hostname and the API server certificate includes it as a SAN.

## Notes and limitations

- Nodes are configured with `--accept-dns=false`, so their own DNS resolution is unchanged and does not depend on `tailscaled`. Only the machines you administer from need MagicDNS resolution.
- Node registration adds a short delay to first boot. hetzner-k3s automatically waits longer for SSH when Tailscale is enabled.
- **Cluster deletion does not remove nodes from your tailnet.** Remove stale machines from the [admin console](https://login.tailscale.com/admin/machines) after deleting a cluster. If you recreate a cluster with the same names while stale entries exist, Tailscale appends a numeric suffix to the new nodes' DNS names, which breaks Tailscale-based SSH access.
- IPv6-only nodes (no public IPv4) are not covered by this integration.
