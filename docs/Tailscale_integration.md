# Tailscale integration

hetzner-k3s supports first-class Tailscale integration, allowing you to provision cluster nodes with **no public IPv4 addresses** while still managing them over SSH through your [Tailscale](https://tailscale.com) tailnet. Once Tailscale is installed and authenticated during cloud-init, all subsequent provisioning SSH connections are routed through MagicDNS hostnames rather than public IPs.

This is the recommended approach for hardened clusters where you want nodes to be unreachable from the public internet while retaining full management capability.

## How it works

When `use_tailscale: true` is set, hetzner-k3s injects the following into each node's cloud-init bootstrap sequence (immediately after `hostnamectl` sets the hostname):

1. Installs Tailscale via the official install script (`curl -fsSL https://tailscale.com/install.sh | sh`)
2. Authenticates and registers the node with your tailnet (`tailscale up --authkey=... --hostname=$(hostname) --accept-routes`)

After cloud-init completes, hetzner-k3s uses the MagicDNS hostname (`<instance-name>.<tailnet-name>.ts.net`) for all SSH connections instead of the node's public or private IP address.

The Tailscale machine name is guaranteed to match the Hetzner instance name because `tailscale up --hostname=$(hostname)` runs after `hostnamectl` has already set the hostname from the Hetzner metadata API.

## Prerequisites

- A Tailscale account with MagicDNS enabled (Settings → DNS → Enable MagicDNS)
- A **reusable, pre-approved** auth key (not ephemeral — nodes are long-lived servers). Tagged keys are recommended for ACL scoping. Generate one at https://login.tailscale.com/admin/settings/keys.
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
    enabled: false
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
    enabled: false
  allowed_networks:
    ssh:
      - 0.0.0.0/0
    api:
      - 0.0.0.0/0

masters_pool:
  instance_type: cpx21
  instance_count: 3
  location: fsn1

worker_node_pools:
  - name: workers
    instance_type: cpx31
    instance_count: 3
    location: fsn1
```

Run with the auth key exported:

```bash
export TAILSCALE_AUTH_KEY="tskey-auth-..."
hetzner-k3s create --config cluster.yaml
```

## Bootstrap sequence

For reference, here is the order of operations during node provisioning when Tailscale is enabled:

1. `hostnamectl set-hostname <name>` — sets the hostname from Hetzner metadata
2. `update-crypto-policies --set DEFAULT:SHA1 || true`
3. `curl -fsSL https://tailscale.com/install.sh | sh` — installs Tailscale
4. `tailscale up --authkey=... --hostname=$(hostname) --accept-routes` — joins the tailnet
5. `/etc/configure_ssh.sh` — configures SSH port
6. DNS resolver setup
7. (Optional) local firewall setup

After step 4, the node is reachable on the tailnet as `<instance-name>.<tailnet-name>.ts.net`. hetzner-k3s retries SSH in a loop (step `wait_for_instance`) which naturally handles the short delay while steps 3–4 complete.
