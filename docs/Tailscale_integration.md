# Tailscale integration

hetzner-k3s can install [Tailscale](https://tailscale.com) on every cluster node during provisioning and join them to your tailnet. This gives you a private administrative path to the nodes (SSH) and to the Kubernetes API, without exposing them to the public internet or maintaining CIDR allowlists for changing IPs (home, coworking, travel).

When enabled:

1. Each node installs Tailscale in cloud-init and joins the tailnet as `<instance-name>.<hostname_suffix>` (MagicDNS name).
2. All SSH connections made by hetzner-k3s itself (provisioning, upgrades, `run` commands) go through the tailnet instead of public or private IPs.
3. The API server certificate gets a TLS SAN for each master's Tailscale hostname, and the generated kubeconfig points to `https://<first-master>.<hostname_suffix>:6443`.

## Prerequisites

- A Tailscale account with MagicDNS enabled (Settings > DNS > Enable MagicDNS).
- A **reusable, pre-approved** auth key. Nodes are long-lived servers, so ephemeral keys are not suitable. Tagged keys are recommended for ACL scoping (e.g. `tag:k8s-nodes`). Generate one at <https://login.tailscale.com/admin/settings/keys>.
- The machine running hetzner-k3s must be connected to the same tailnet, with the `tailscale` CLI installed and signed in (`tailscale up`). hetzner-k3s reads peer state from `tailscale status --json`, and fails immediately with an explicit error if the CLI is missing, the daemon is not running, or the machine is not logged in.
- Nodes need a supported image for the automatic install: Debian, Ubuntu, or a RHEL-family distribution (RHEL, Rocky Linux, AlmaLinux, CentOS, Fedora). For MicroOS snapshots or any other image, install Tailscale in the snapshot yourself and use `enabled: false` plus your own `pre_k3s_commands`.

## Configuration

```yaml
networking:
  tailscale:
    enabled: true
    hostname_suffix: "my-tailnet.ts.net" # your tailnet's MagicDNS domain, found in the admin console under DNS
    # auth_key: "tskey-auth-..." # optional: defaults to the TAILSCALE_AUTH_KEY environment variable
    # version: "1.80.2"          # optional: pin the package version instead of the repository's current stable
```

The auth key can be supplied in two ways:

| Method | How |
|--------|-----|
| Environment variable (recommended) | `export TAILSCALE_AUTH_KEY="tskey-auth-..."` |
| Config file | `auth_key: "tskey-auth-..."` in the `tailscale:` block |

### Installation

Tailscale is installed from Tailscale's signed package repository, not with the upstream `curl https://tailscale.com/install.sh | sh` script. On Debian and Ubuntu the apt repository is added and the `tailscale` package installed; on RHEL-family distributions the dnf repository is used. If the image does not have a supported package manager the boot step fails with an explicit message in `/var/log/hetzner-k3s.log` instead of silently leaving the node without Tailscale.

Set `version` to install an exact package version. When it is empty, the repository's current stable package is installed, and the installed version is logged during boot.

### Auth key handling

The key is written to `/run/tailscale-authkey` (mode `0600`, tmpfs) and deleted right after `tailscale up` runs. That keeps the window short, but it is **not** the only copy on the node: cloud-init keeps the complete user-data, key included, at `/var/lib/cloud/instance/user-data.txt` for the life of the instance, and the key also exists in your configuration file or environment and in the user-data sent to the Hetzner API.

Treat the key as a long-lived credential: scope it with a tag and ACLs, and revoke or rotate it once the cluster exists rather than leaving a reusable key valid indefinitely.

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

Two caveats:

- The `api` allowlist only controls port 6443 when the private network is enabled (cloud firewall path) or `public_network.use_local_firewall: true` (node firewall path). With a public-only cluster and the Hetzner cloud firewall, 6443 stays open to the internet regardless of `allowed_networks.api`.
- The SSH allowlist behaves the same way: it is enforced by the cloud firewall when the private network is enabled, or by the local firewall otherwise.

With this setup, `kubectl` works from any machine connected to the tailnet, because the kubeconfig points to the master's MagicDNS hostname and the API server certificate includes it as a SAN.

## Notes and limitations

- Nodes are configured with `--accept-dns=false`, so their own DNS resolution is unchanged and does not depend on `tailscaled`. Only the machines you administer from need MagicDNS resolution.
- Subnet routes are **not** accepted: `--accept-routes` is not passed, so a subnet router advertising a supernet such as `10.0.0.0/8` cannot take over the private network, pod or service CIDRs.
- Node registration adds a short delay to first boot. hetzner-k3s retries SSH for up to 5 minutes when Tailscale is enabled, because the node has to install the package and join the tailnet before SSH is reachable.
- **External node pools are not covered.** External (generic SSH and Robot) nodes never run cloud-init, so hetzner-k3s keeps connecting to them over their configured host and IP. A cluster that mixes external pools with `tailscale.enabled: true` only routes the Hetzner-provisioned nodes over the tailnet.
- **Cluster deletion does not remove nodes from your tailnet.** Remove stale machines from the [admin console](https://login.tailscale.com/admin/machines) after deleting a cluster. If you recreate a cluster with the same names while stale entries exist, Tailscale appends a numeric suffix to the new nodes' DNS names, which breaks Tailscale-based SSH access.
- IPv6-only nodes (no public IPv4) are not covered by this integration.
